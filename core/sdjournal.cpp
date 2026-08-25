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
#include "sdjournal.h"
//---------------------------------------------------------------------------

#ifndef _WIN32
	#include <sys/un.h>

static const char g_sJournalSocket[] = "/run/systemd/journal/socket";

// -1 until probed
static int g_iJournalSock = -1;

static int JournalSocket() {
	if(g_iJournalSock != -1) {
		return g_iJournalSock;
	}

	struct stat st;
	if(stat(g_sJournalSocket, &st) == -1 || S_ISSOCK(st.st_mode) == 0) {
		g_iJournalSock = -2;
		return -2;
	}

	g_iJournalSock = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);

	if(g_iJournalSock == -1) {
		g_iJournalSock = -2;
	}

	return g_iJournalSock;
}
#endif
//---------------------------------------------------------------------------

bool PxJournalSend(const int iPriority, const char * sSubsystem, const char * sMsg,
	const char * sField, const char * sValue) {
#ifdef _WIN32
	(void)iPriority; (void)sSubsystem; (void)sMsg; (void)sField; (void)sValue;
	return false;
#else
	const int iSock = JournalSocket();

	if(iSock < 0 || sMsg == NULL) {
		return false;
	}

	char sBuf[4096];
	int iLen = snprintf(sBuf, sizeof(sBuf), "PRIORITY=%d\nPTOKAX_SUBSYSTEM=%s\n",
		iPriority, sSubsystem != NULL ? sSubsystem : "hub");

	if(iLen <= 0 || (size_t)iLen >= sizeof(sBuf)) {
		return false;
	}

	if(sField != NULL && sValue != NULL) {
		const int iAdd = snprintf(sBuf + iLen, sizeof(sBuf) - iLen, "%s=%s\n", sField, sValue);

		if(iAdd <= 0 || (size_t)iAdd >= sizeof(sBuf) - iLen) {
			return false;
		}

		iLen += iAdd;
	}

	// a message may contain newlines, so it uses the length-prefixed form
	const uint64_t ui64MsgLen = (uint64_t)strlen(sMsg);

	if((size_t)iLen + 9 + ui64MsgLen + 1 > sizeof(sBuf)) {
		return false;
	}

	memcpy(sBuf + iLen, "MESSAGE\n", 8);
	iLen += 8;

	for(int i = 0; i < 8; i++) {
		sBuf[iLen++] = (char)((ui64MsgLen >> (i * 8)) & 0xFF);
	}

	memcpy(sBuf + iLen, sMsg, (size_t)ui64MsgLen);
	iLen += (int)ui64MsgLen;
	sBuf[iLen++] = '\n';

	struct sockaddr_un sun;
	memset(&sun, 0, sizeof(sun));
	sun.sun_family = AF_UNIX;
	memcpy(sun.sun_path, g_sJournalSocket, sizeof(g_sJournalSocket) - 1);

	return sendto(iSock, sBuf, (size_t)iLen, MSG_NOSIGNAL,
		(struct sockaddr *)&sun, (socklen_t)sizeof(sun)) >= 0;
#endif
}
//---------------------------------------------------------------------------
