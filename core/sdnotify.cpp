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
#include "sdnotify.h"
//---------------------------------------------------------------------------

#ifndef _WIN32
	#include <sys/un.h>
#endif
//---------------------------------------------------------------------------

bool PxNotify(const char * sState) {
#ifdef _WIN32
	(void)sState;
	return false;
#else
	const char * sSocket = getenv("NOTIFY_SOCKET");

	if(sSocket == NULL || sState == NULL || *sState == '\0') {
		return false;
	}

	if(sSocket[0] != '/' && sSocket[0] != '@') {
		return false;
	}

	struct sockaddr_un sun;
	memset(&sun, 0, sizeof(sun));
	sun.sun_family = AF_UNIX;

	const size_t szLen = strlen(sSocket);
	if(szLen >= sizeof(sun.sun_path)) {
		return false;
	}

	memcpy(sun.sun_path, sSocket, szLen);

	// "@" selects the abstract namespace, which starts with a NUL
	if(sun.sun_path[0] == '@') {
		sun.sun_path[0] = '\0';
	}

	const int iSock = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if(iSock == -1) {
		return false;
	}

	const socklen_t sunLen = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + szLen);

	const ssize_t sszSent = sendto(iSock, sState, strlen(sState), MSG_NOSIGNAL,
		(struct sockaddr *)&sun, sunLen);

	close(iSock);

	return sszSent >= 0;
#endif
}
//---------------------------------------------------------------------------

bool PxNotifyFormat(const char * sFormat, ...) {
#ifndef _WIN32
	if(getenv("NOTIFY_SOCKET") == NULL) {
		return false;
	}
#endif

	char sBuf[1024];

	va_list vlArgs;
	va_start(vlArgs, sFormat);
	const int iLen = vsnprintf(sBuf, sizeof(sBuf), sFormat, vlArgs);
	va_end(vlArgs);

	if(iLen <= 0) {
		return false;
	}

	return PxNotify(sBuf);
}
//---------------------------------------------------------------------------
