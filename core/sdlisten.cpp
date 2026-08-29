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
#include "sdlisten.h"
#include "logging.h"
//---------------------------------------------------------------------------

#ifndef _WIN32

static const int PX_LISTEN_FDS_START = 3;
static const size_t PX_MAX_LISTEN_FDS = 64;
static const size_t PX_LISTEN_FD_NAMELEN = 64;

struct PxListenFd {
	int iFd;
	int iFamily;
	uint16_t ui16Port;
	bool bClaimed;
	char sName[PX_LISTEN_FD_NAMELEN];
};

static PxListenFd g_ListenFds[PX_MAX_LISTEN_FDS];
static size_t g_szListenFds = 0;

static void PxFdName(const char * sNames, const long lIdx, char * sOut, const size_t szOut) {
	sOut[0] = '\0';

	if(sNames == NULL || *sNames == '\0') {
		return;
	}

	const char * sCur = sNames;

	for(long li = 0; li < lIdx; li++) {
		const char * sSep = strchr(sCur, ':');

		if(sSep == NULL) {
			return;
		}

		sCur = sSep + 1;
	}

	const char * sEnd = strchr(sCur, ':');
	size_t szLen = sEnd != NULL ? (size_t)(sEnd - sCur) : strlen(sCur);

	if(szLen >= szOut) {
		szLen = szOut - 1;
	}

	memcpy(sOut, sCur, szLen);
	sOut[szLen] = '\0';
}

#endif
//---------------------------------------------------------------------------

void PxListenFdsInit() {
#ifndef _WIN32
	const char * sPid = getenv("LISTEN_PID");
	const char * sFds = getenv("LISTEN_FDS");

	if(sPid == NULL || sFds == NULL) {
		return;
	}

	const long lPid = strtol(sPid, NULL, 10);
	const long lFds = strtol(sFds, NULL, 10);

	// the names have to be copied out before the environment is cleared below
	char sNames[1024];
	const char * sEnvNames = getenv("LISTEN_FDNAMES");

	if(sEnvNames != NULL) {
		snprintf(sNames, sizeof(sNames), "%s", sEnvNames);
	} else {
		sNames[0] = '\0';
	}

	unsetenv("LISTEN_PID");
	unsetenv("LISTEN_FDS");
	unsetenv("LISTEN_FDNAMES");

	if(lPid != (long)getpid() || lFds <= 0) {
		return;
	}

	for(long li = 0; li < lFds && g_szListenFds < PX_MAX_LISTEN_FDS; li++) {
		const int iFd = PX_LISTEN_FDS_START + (int)li;

		int iType = 0;
		socklen_t szType = sizeof(iType);
		if(getsockopt(iFd, SOL_SOCKET, SO_TYPE, &iType, &szType) == -1 || iType != SOCK_STREAM) {
			continue;
		}

		int iAccept = 0;
		socklen_t szAccept = sizeof(iAccept);
		if(getsockopt(iFd, SOL_SOCKET, SO_ACCEPTCONN, &iAccept, &szAccept) == -1 || iAccept == 0) {
			continue;
		}

		sockaddr_storage sas;
		socklen_t szSas = sizeof(sas);
		if(getsockname(iFd, (struct sockaddr *)&sas, &szSas) == -1) {
			continue;
		}

		uint16_t ui16Port = 0;
		if(sas.ss_family == AF_INET6) {
			ui16Port = ntohs(((struct sockaddr_in6 *)&sas)->sin6_port);
		} else if(sas.ss_family == AF_INET) {
			ui16Port = ntohs(((struct sockaddr_in *)&sas)->sin_port);
		} else if(sas.ss_family != AF_UNIX) {
			continue;
		}

		fcntl(iFd, F_SETFD, FD_CLOEXEC);

		PxListenFd * pFd = &g_ListenFds[g_szListenFds];

		pFd->iFd = iFd;
		pFd->iFamily = (int)sas.ss_family;
		pFd->ui16Port = ui16Port;
		pFd->bClaimed = false;
		PxFdName(sNames, li, pFd->sName, PX_LISTEN_FD_NAMELEN);
		g_szListenFds++;

		if(sas.ss_family == AF_UNIX) {
			LogEmitFormat(PX_LOG_INFO, PX_SUB_HUB, "Inherited listening socket named %s (unix)",
				pFd->sName[0] != '\0' ? pFd->sName : "?");
		} else {
			LogEmitFormat(PX_LOG_INFO, PX_SUB_HUB, "Inherited listening socket on port %hu (%s)",
				ui16Port, sas.ss_family == AF_INET6 ? "IPv6" : "IPv4");
		}
	}
#endif
}
//---------------------------------------------------------------------------

bool PxAdoptListenFd(const int iFamily, const uint16_t ui16Port, int * piFd) {
#ifndef _WIN32
	for(size_t szi = 0; szi < g_szListenFds; szi++) {
		if(g_ListenFds[szi].bClaimed == true) {
			continue;
		}

		if(g_ListenFds[szi].iFamily != iFamily || g_ListenFds[szi].ui16Port != ui16Port) {
			continue;
		}

		g_ListenFds[szi].bClaimed = true;
		*piFd = g_ListenFds[szi].iFd;
		return true;
	}
#else
	(void)iFamily; (void)ui16Port; (void)piFd;
#endif

	return false;
}
//---------------------------------------------------------------------------

bool PxAdoptListenFdByName(const char * sName, int * piFd) {
#ifndef _WIN32
	if(sName == NULL || *sName == '\0') {
		return false;
	}

	for(size_t szi = 0; szi < g_szListenFds; szi++) {
		if(g_ListenFds[szi].bClaimed == true) {
			continue;
		}

		if(strcmp(g_ListenFds[szi].sName, sName) != 0) {
			continue;
		}

		g_ListenFds[szi].bClaimed = true;
		*piFd = g_ListenFds[szi].iFd;
		return true;
	}
#else
	(void)sName; (void)piFd;
#endif

	return false;
}
//---------------------------------------------------------------------------

void PxReleaseListenFd(const int iFd) {
#ifndef _WIN32
	for(size_t szi = 0; szi < g_szListenFds; szi++) {
		if(g_ListenFds[szi].iFd == iFd) {
			g_ListenFds[szi].bClaimed = false;
			return;
		}
	}
#else
	(void)iFd;
#endif
}
//---------------------------------------------------------------------------

bool PxIsListenFd(const int iFd) {
#ifndef _WIN32
	for(size_t szi = 0; szi < g_szListenFds; szi++) {
		if(g_ListenFds[szi].iFd == iFd) {
			return true;
		}
	}
#else
	(void)iFd;
#endif

	return false;
}
//---------------------------------------------------------------------------

void PxReportUnclaimedFds() {
#ifndef _WIN32
	for(size_t szi = 0; szi < g_szListenFds; szi++) {
		if(g_ListenFds[szi].bClaimed == false) {
			if(g_ListenFds[szi].iFamily == AF_UNIX) {
				LogEmitFormat(PX_LOG_WARNING, PX_SUB_HUB,
					"systemd passed a listening socket named %s that nothing claimed; nothing will accept on it",
					g_ListenFds[szi].sName[0] != '\0' ? g_ListenFds[szi].sName : "?");
			} else {
				LogEmitFormat(PX_LOG_WARNING, PX_SUB_HUB,
					"systemd passed a listening socket on port %hu that is not in TCPPorts; nothing will accept on it",
					g_ListenFds[szi].ui16Port);
			}
		}
	}
#endif
}
//---------------------------------------------------------------------------
