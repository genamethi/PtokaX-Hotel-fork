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
#ifndef ProxyProtocolH
#define ProxyProtocolH
//---------------------------------------------------------------------------

// Header formats a TLS terminator puts in front of the NMDC stream.
//
//   nginx                     PROXY protocol v2 binary header
//   tls-proxy, FearTLS        $MyIP <ip> <tlsver>|
//
// Both carry the client address the hub must use in place of the proxy's own.

enum PxProxyResult {
	PX_PROXY_OK,
	PX_PROXY_NEED_MORE,	// nothing wrong yet, the header is not all here
	PX_PROXY_BAD
};

struct PxProxyHeader {
	sockaddr_storage m_Addr;
	size_t m_szConsumed;
	bool m_bSecure;
	char m_sTLSVersion[8];	// bare version, "1.3", empty when not secure
};

// Never reads the socket. szLen is what has arrived so far.
PxProxyResult PxProxyParse(const char * pBuf, const size_t szLen, PxProxyHeader &Header);

// Longest header worth waiting for. PPv2 allows 65535 bytes of address plus TLVs,
// but nginx writes at most a few hundred and $MyIP is under 32.
static const size_t PX_PROXY_MAX_HEADER = 1024;

//---------------------------------------------------------------------------
#endif
