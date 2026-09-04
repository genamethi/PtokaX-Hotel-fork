/*
 * PtokaX - hub server for Direct Connect peer to peer network.

 * Copyright (C) 2004-2022  Petr Kozelka, PPK at PtokaX dot org

 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3
 * as published by the Free Software Foundation.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
//---------------------------------------------------------------------------
#include "stdinc.h"
//---------------------------------------------------------------------------
#include "ProxyProtocol.h"
//---------------------------------------------------------------------------

static const char PX_PPV2_SIG[12] = {
	'\x0D', '\x0A', '\x0D', '\x0A', '\x00', '\x0D',
	'\x0A', '\x51', '\x55', '\x49', '\x54', '\x0A'
};

static const size_t PX_PPV2_HDRLEN = 16;

static const uint8_t PX_PPV2_VER          = 0x20;
static const uint8_t PX_PPV2_CMD_LOCAL    = 0x00;
static const uint8_t PX_PPV2_CMD_PROXY    = 0x01;

static const uint8_t PX_PPV2_AF_INET      = 0x01;
static const uint8_t PX_PPV2_AF_INET6     = 0x02;
static const uint8_t PX_PPV2_AF_UNIX      = 0x03;

static const uint8_t PX_PPV2_TLV_SSL      = 0x20;
static const uint8_t PX_PPV2_TLV_SSL_VER  = 0x21;

// first byte of the 0x20 value, set by the sender when the client used TLS
static const uint8_t PX_PPV2_CLIENT_SSL   = 0x01;

static const char PX_MYIP_PREFIX[] = "$MyIP ";
static const size_t PX_MYIP_PREFIXLEN = sizeof(PX_MYIP_PREFIX) - 1;

//---------------------------------------------------------------------------

// tls-proxy sends "1.3", nginx sends "TLSv1.3". Scripts get one form.
static void PxStoreVersion(const char * pVal, const size_t szLen, char * sOut, const size_t szOut) {
	const char * pSrc = pVal;
	size_t szSrc = szLen;

	if(szSrc > 4 && memcmp(pSrc, "TLSv", 4) == 0) {
		pSrc += 4;
		szSrc -= 4;
	}

	if(szSrc >= szOut) {
		szSrc = szOut - 1;
	}

	memcpy(sOut, pSrc, szSrc);
	sOut[szSrc] = '\0';
}
//---------------------------------------------------------------------------

// The 0x20 value is a client byte, a 4 byte verify result, then sub-TLVs.
static void PxParseSslTlv(const uint8_t * pVal, const size_t szLen, PxProxyHeader &Header) {
	if(szLen < 5) {
		return;
	}

	if((pVal[0] & PX_PPV2_CLIENT_SSL) != PX_PPV2_CLIENT_SSL) {
		return;
	}

	Header.m_bSecure = true;

	size_t szPos = 5;

	while(szPos + 3 <= szLen) {
		const uint8_t ui8Type = pVal[szPos];
		const size_t szSubLen = ((size_t)pVal[szPos+1] << 8) | (size_t)pVal[szPos+2];

		szPos += 3;

		if(szPos + szSubLen > szLen) {
			return;
		}

		if(ui8Type == PX_PPV2_TLV_SSL_VER) {
			PxStoreVersion((const char *)(pVal + szPos), szSubLen, Header.m_sTLSVersion, sizeof(Header.m_sTLSVersion));
		}

		szPos += szSubLen;
	}
}
//---------------------------------------------------------------------------

static PxProxyResult PxParsePPv2(const char * pBuf, const size_t szLen, PxProxyHeader &Header) {
	if(szLen < PX_PPV2_HDRLEN) {
		return PX_PROXY_NEED_MORE;
	}

	const uint8_t * pu = (const uint8_t *)pBuf;

	if((pu[12] & 0xF0) != PX_PPV2_VER) {
		return PX_PROXY_BAD;
	}

	const uint8_t ui8Cmd = pu[12] & 0x0F;

	if(ui8Cmd != PX_PPV2_CMD_PROXY && ui8Cmd != PX_PPV2_CMD_LOCAL) {
		return PX_PROXY_BAD;
	}

	const size_t szBodyLen = ((size_t)pu[14] << 8) | (size_t)pu[15];

	if(PX_PPV2_HDRLEN + szBodyLen > PX_PROXY_MAX_HEADER) {
		return PX_PROXY_BAD;
	}

	if(szLen < PX_PPV2_HDRLEN + szBodyLen) {
		return PX_PROXY_NEED_MORE;
	}

	// LOCAL carries no address, so there is nothing to attribute the connection to
	if(ui8Cmd == PX_PPV2_CMD_LOCAL) {
		return PX_PROXY_BAD;
	}

	const uint8_t ui8Family = (pu[13] & 0xF0) >> 4;

	const uint8_t * pBody = pu + PX_PPV2_HDRLEN;
	size_t szAddrLen = 0;

	memset(&Header.m_Addr, 0, sizeof(sockaddr_storage));

	if(ui8Family == PX_PPV2_AF_INET) {
		szAddrLen = 12;

		if(szBodyLen < szAddrLen) {
			return PX_PROXY_BAD;
		}

		sockaddr_in * pIn = (sockaddr_in *)&Header.m_Addr;
		pIn->sin_family = AF_INET;
		memcpy(&pIn->sin_addr, pBody, 4);
		memcpy(&pIn->sin_port, pBody + 8, 2);
	} else if(ui8Family == PX_PPV2_AF_INET6) {
		szAddrLen = 36;

		if(szBodyLen < szAddrLen) {
			return PX_PROXY_BAD;
		}

		sockaddr_in6 * pIn6 = (sockaddr_in6 *)&Header.m_Addr;
		pIn6->sin6_family = AF_INET6;
		memcpy(&pIn6->sin6_addr, pBody, 16);
		memcpy(&pIn6->sin6_port, pBody + 32, 2);
	} else if(ui8Family == PX_PPV2_AF_UNIX) {
		return PX_PROXY_BAD;
	} else {
		return PX_PROXY_BAD;
	}

	size_t szPos = szAddrLen;

	while(szPos + 3 <= szBodyLen) {
		const uint8_t ui8Type = pBody[szPos];
		const size_t szTlvLen = ((size_t)pBody[szPos+1] << 8) | (size_t)pBody[szPos+2];

		szPos += 3;

		if(szPos + szTlvLen > szBodyLen) {
			return PX_PROXY_BAD;
		}

		// everything else, CRC32C and ALPN included, is skipped by length
		if(ui8Type == PX_PPV2_TLV_SSL) {
			PxParseSslTlv(pBody + szPos, szTlvLen, Header);
		}

		szPos += szTlvLen;
	}

	Header.m_szConsumed = PX_PPV2_HDRLEN + szBodyLen;

	return PX_PROXY_OK;
}
//---------------------------------------------------------------------------

static PxProxyResult PxParseMyIP(const char * pBuf, const size_t szLen, PxProxyHeader &Header) {
	const char * pEnd = (const char *)memchr(pBuf, '|', szLen);

	if(pEnd == NULL) {
		return szLen < PX_PROXY_MAX_HEADER ? PX_PROXY_NEED_MORE : PX_PROXY_BAD;
	}

	const char * pAddr = pBuf + PX_MYIP_PREFIXLEN;

	const char * pSep = (const char *)memchr(pAddr, ' ', (size_t)(pEnd - pAddr));

	if(pSep == NULL) {
		return PX_PROXY_BAD;
	}

	const size_t szAddrLen = (size_t)(pSep - pAddr);

	if(szAddrLen == 0 || szAddrLen > 45) {
		return PX_PROXY_BAD;
	}

	char sAddr[46];
	memcpy(sAddr, pAddr, szAddrLen);
	sAddr[szAddrLen] = '\0';

	memset(&Header.m_Addr, 0, sizeof(sockaddr_storage));

	sockaddr_in * pIn = (sockaddr_in *)&Header.m_Addr;

	if(inet_pton(AF_INET, sAddr, &pIn->sin_addr) == 1) {
		pIn->sin_family = AF_INET;
	} else {
		sockaddr_in6 * pIn6 = (sockaddr_in6 *)&Header.m_Addr;

		if(inet_pton(AF_INET6, sAddr, &pIn6->sin6_addr) != 1) {
			return PX_PROXY_BAD;
		}

		pIn6->sin6_family = AF_INET6;
	}

	const char * pVer = pSep + 1;
	const size_t szVerLen = (size_t)(pEnd - pVer);

	// "0.0" is what both proxies send for a client that did not use TLS
	if(szVerLen != 0 && (szVerLen != 3 || memcmp(pVer, "0.0", 3) != 0)) {
		Header.m_bSecure = true;
		PxStoreVersion(pVer, szVerLen, Header.m_sTLSVersion, sizeof(Header.m_sTLSVersion));
	}

	Header.m_szConsumed = (size_t)(pEnd - pBuf) + 1;

	return PX_PROXY_OK;
}
//---------------------------------------------------------------------------

PxProxyResult PxProxyParse(const char * pBuf, const size_t szLen, PxProxyHeader &Header) {
	memset(&Header.m_Addr, 0, sizeof(sockaddr_storage));
	Header.m_szConsumed = 0;
	Header.m_bSecure = false;
	Header.m_sTLSVersion[0] = '\0';

	if(szLen == 0) {
		return PX_PROXY_NEED_MORE;
	}

	const size_t szSigCmp = szLen < sizeof(PX_PPV2_SIG) ? szLen : sizeof(PX_PPV2_SIG);

	if(memcmp(pBuf, PX_PPV2_SIG, szSigCmp) == 0) {
		return szSigCmp < sizeof(PX_PPV2_SIG) ? PX_PROXY_NEED_MORE : PxParsePPv2(pBuf, szLen, Header);
	}

	const size_t szPfxCmp = szLen < PX_MYIP_PREFIXLEN ? szLen : PX_MYIP_PREFIXLEN;

	if(memcmp(pBuf, PX_MYIP_PREFIX, szPfxCmp) == 0) {
		return szPfxCmp < PX_MYIP_PREFIXLEN ? PX_PROXY_NEED_MORE : PxParseMyIP(pBuf, szLen, Header);
	}

	return PX_PROXY_BAD;
}
//---------------------------------------------------------------------------
