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
#include "LuaInc.h"
//---------------------------------------------------------------------------
#include "LuaConsole.h"
#include "LuaScript.h"
#include "LuaScriptManager.h"
#include "logging.h"
#include "sdlisten.h"
#include "ServerManager.h"
//---------------------------------------------------------------------------

#ifndef _WIN32

static const char PX_CONSOLE_FD_NAME[] = "console";
static const size_t PX_CONSOLE_MAX_CONNS = 4;
static const size_t PX_CONSOLE_MAX_CHUNK = 1048576;
static const size_t PX_CONSOLE_READ_SIZE = 4096;
static const time_t PX_CONSOLE_TIMEOUT = 30;
static const time_t PX_CONSOLE_REPLY_TIMEOUT = 2;

struct PxConsoleConn {
	int iFd;
	char * sBuf;
	size_t szLen;
	size_t szCap;
	time_t tDeadline;
};

static int g_iListenFd = -1;
static PxConsoleConn g_Conns[PX_CONSOLE_MAX_CONNS];
static size_t g_szConns = 0;

static int ConsolePrint(lua_State * pLua) {
	const int iArgs = lua_gettop(pLua);

	int iPieces = 0;

	for(int i = 1; i <= iArgs; i++) {
		if(i > 1) {
			lua_pushliteral(pLua, "\t");
			iPieces++;
		}

#if LUA_VERSION_NUM > 501
		luaL_tolstring(pLua, i, NULL);
#else
		lua_getglobal(pLua, "tostring");
		lua_pushvalue(pLua, i);
		lua_call(pLua, 1, 1);
#endif

		iPieces++;
	}

	lua_concat(pLua, iPieces);

	const char * sOut = lua_tostring(pLua, -1);

	if(sOut != NULL) {
		LogEmitJournal(PX_LOG_INFO, PX_SUB_CONSOLE, sOut);
	}

	lua_pop(pLua, 1);

	return 0;
}
//---------------------------------------------------------------------------

static void ConsoleEval(const char * sChunk, const size_t szChunk) {
	lua_State * pLua = luaL_newstate();

	if(pLua == NULL) {
		LogEmitJournal(PX_LOG_ERR, PX_SUB_CONSOLE, "Cannot create console Lua state");
		return;
	}

	LuaStateInit(pLua);

	lua_pushcfunction(pLua, ConsolePrint);
	lua_setglobal(pLua, "print");

	lua_pushcfunction(pLua, ScriptTraceback);
	const int iTraceback = lua_gettop(pLua);

	// a console typo must not reach ScriptError, which can stop a script
	if(luaL_loadbuffer(pLua, sChunk, szChunk, "=console") != 0 ||
		lua_pcall(pLua, 0, 0, iTraceback) != 0) {
		const char * sMsg = lua_tostring(pLua, -1);

		LogEmitJournal(PX_LOG_ERR, PX_SUB_CONSOLE, sMsg != NULL ? sMsg : "unknown error");
	}

	lua_close(pLua);
}
//---------------------------------------------------------------------------

static bool ConnAppend(PxConsoleConn * pConn, const char * sData, const size_t szData) {
	if(pConn->szLen + szData > PX_CONSOLE_MAX_CHUNK) {
		return false;
	}

	if(pConn->szLen + szData + 1 > pConn->szCap) {
		size_t szNew = pConn->szCap != 0 ? pConn->szCap : PX_CONSOLE_READ_SIZE;

		while(szNew < pConn->szLen + szData + 1) {
			szNew *= 2;
		}

		char * sNew = (char *)realloc(pConn->sBuf, szNew);

		if(sNew == NULL) {
			return false;
		}

		pConn->sBuf = sNew;
		pConn->szCap = szNew;
	}

	memcpy(pConn->sBuf + pConn->szLen, sData, szData);
	pConn->szLen += szData;
	pConn->sBuf[pConn->szLen] = '\0';

	return true;
}
//---------------------------------------------------------------------------

static void ConnDrop(const size_t szIdx) {
	if(g_Conns[szIdx].iFd != -1) {
		close(g_Conns[szIdx].iFd);
	}

	free(g_Conns[szIdx].sBuf);

	if(szIdx + 1 < g_szConns) {
		g_Conns[szIdx] = g_Conns[g_szConns - 1];
	}

	g_szConns--;
}
//---------------------------------------------------------------------------

static void ConsoleAccept() {
	for(;;) {
		const int iFd = accept(g_iListenFd, NULL, NULL);

		if(iFd == -1) {
			return;
		}

		if(g_szConns >= PX_CONSOLE_MAX_CONNS) {
			close(iFd);
			continue;
		}

		const int iFlags = fcntl(iFd, F_GETFL, 0);

		if(iFlags != -1) {
			fcntl(iFd, F_SETFL, iFlags | O_NONBLOCK);
		}

		fcntl(iFd, F_SETFD, FD_CLOEXEC);

		PxConsoleConn * pConn = &g_Conns[g_szConns];

		pConn->iFd = iFd;
		pConn->sBuf = NULL;
		pConn->szLen = 0;
		pConn->szCap = 0;
		pConn->tDeadline = time(NULL) + PX_CONSOLE_TIMEOUT;

		g_szConns++;
	}
}
//---------------------------------------------------------------------------

static void ConsoleReplyMode(const int iFd) {
	const int iFlags = fcntl(iFd, F_GETFL, 0);

	if(iFlags != -1) {
		fcntl(iFd, F_SETFL, iFlags & ~O_NONBLOCK);
	}

	struct timeval tv;

	tv.tv_sec = PX_CONSOLE_REPLY_TIMEOUT;
	tv.tv_usec = 0;

	setsockopt(iFd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}
//---------------------------------------------------------------------------

static void ConsoleWrite(const int iFd, const char * sMsg) {
	const size_t szLen = strlen(sMsg);

	for(size_t szSent = 0; szSent < szLen; ) {
		const ssize_t sszSent = send(iFd, sMsg + szSent, szLen - szSent, MSG_NOSIGNAL);

		if(sszSent > 0) {
			szSent += (size_t)sszSent;
			continue;
		}

		if(sszSent == -1 && errno == EINTR) {
			continue;
		}

		return;
	}
}
//---------------------------------------------------------------------------

static bool ConsoleDirective(const char * sBuf, const size_t szLen, char * sVerb,
	const size_t szVerbMax, char * sArg, const size_t szArgMax) {
	static const char sMark[] = "--!px";

	size_t szEnd = szLen;

	while(szEnd > 0 && (sBuf[szEnd - 1] == '\n' || sBuf[szEnd - 1] == '\r')) {
		szEnd--;
	}

	size_t szPos = szEnd;

	while(szPos > 0 && sBuf[szPos - 1] != '\n') {
		szPos--;
	}

	if(szEnd - szPos < sizeof(sMark) - 1 || strncmp(sBuf + szPos, sMark, sizeof(sMark) - 1) != 0) {
		return false;
	}

	szPos += sizeof(sMark) - 1;

	if(szPos < szEnd && sBuf[szPos] != ' ' && sBuf[szPos] != '\t') {
		return false;
	}

	while(szPos < szEnd && (sBuf[szPos] == ' ' || sBuf[szPos] == '\t')) {
		szPos++;
	}

	size_t szi = 0;

	while(szPos < szEnd && sBuf[szPos] != ' ' && sBuf[szPos] != '\t') {
		if(szi + 1 < szVerbMax) {
			sVerb[szi++] = sBuf[szPos];
		}

		szPos++;
	}

	sVerb[szi] = '\0';

	if(szi == 0) {
		return false;
	}

	while(szPos < szEnd && (sBuf[szPos] == ' ' || sBuf[szPos] == '\t')) {
		szPos++;
	}

	while(szEnd > szPos && (sBuf[szEnd - 1] == ' ' || sBuf[szEnd - 1] == '\t')) {
		szEnd--;
	}

	szi = 0;

	while(szPos < szEnd && szi + 1 < szArgMax) {
		sArg[szi++] = sBuf[szPos++];
	}

	sArg[szi] = '\0';

	return true;
}
//---------------------------------------------------------------------------

static void ConsoleList(const int iFd) {
	if(ScriptManager::m_Ptr == NULL) {
		ConsoleWrite(iFd, "error: no script manager\n");
		return;
	}

	for(uint8_t ui8i = 0; ui8i < ScriptManager::m_Ptr->m_ui8ScriptCount; ui8i++) {
		Script * pScript = ScriptManager::m_Ptr->m_ppScriptTable[ui8i];

		char sMem[16];

		if(pScript->m_pLua == NULL) {
			sMem[0] = '-';
			sMem[1] = '\0';
		} else {
			snprintf(sMem, sizeof(sMem), "%d", lua_gc(pScript->m_pLua, LUA_GCCOUNT, 0));
		}

		char sRow[2048];

		snprintf(sRow, sizeof(sRow), "%s\t%s\t%s\t%s%s\n", pScript->m_sName,
			pScript->m_bEnabled == true ? "enabled" : "disabled", sMem,
			ServerManager::m_sScriptPath.c_str(), pScript->m_sName);

		ConsoleWrite(iFd, sRow);
	}
}
//---------------------------------------------------------------------------

static bool ConsoleEvalIn(Script * pScript, const char * sChunk, const size_t szChunk,
	char * sErr, const size_t szErrMax) {
	lua_State * pLua = pScript->m_pLua;

	const int iTop = lua_gettop(pLua);

	lua_pushcfunction(pLua, ScriptTraceback);
	const int iTraceback = lua_gettop(pLua);

	bool bOk = true;

	if(luaL_loadbuffer(pLua, sChunk, szChunk, "=console") != 0 ||
		lua_pcall(pLua, 0, 0, iTraceback) != 0) {
		const char * sMsg = lua_tostring(pLua, -1);

		LogEmitJournal(PX_LOG_ERR, PX_SUB_CONSOLE, sMsg != NULL ? sMsg : "unknown error");

		size_t szi = 0;

		if(sMsg != NULL) {
			while(szi + 1 < szErrMax && sMsg[szi] != '\0' && sMsg[szi] != '\n') {
				sErr[szi] = sMsg[szi];
				szi++;
			}
		}

		sErr[szi] = '\0';

		bOk = false;
	}

	lua_settop(pLua, iTop);

	return bOk;
}
//---------------------------------------------------------------------------

static void ConsoleDispatch(const int iFd, char * sChunk, const size_t szChunk) {
	char sVerb[32], sArg[256];

	if(ConsoleDirective(sChunk, szChunk, sVerb, sizeof(sVerb), sArg, sizeof(sArg)) == false) {
		ConsoleEval(sChunk, szChunk);
		return;
	}

	ConsoleReplyMode(iFd);

	if(strcmp(sVerb, "list") == 0) {
		ConsoleList(iFd);
		return;
	}

	if(strcmp(sVerb, "attach") != 0) {
		ConsoleWrite(iFd, "error: unknown directive\n");
		return;
	}

	if(sArg[0] == '\0') {
		ConsoleWrite(iFd, "error: attach needs a script name\n");
		return;
	}

	Script * pScript = ScriptManager::m_Ptr == NULL ? NULL : ScriptManager::m_Ptr->FindScript(sArg);

	if(pScript == NULL) {
		ConsoleWrite(iFd, "error: no such script\n");
		return;
	}

	if(pScript->m_pLua == NULL) {
		ConsoleWrite(iFd, "error: script not running\n");
		return;
	}

	char sErr[512];

	if(ConsoleEvalIn(pScript, sChunk, szChunk, sErr, sizeof(sErr)) == false) {
		char sReply[576];

		snprintf(sReply, sizeof(sReply), "error: %s\n", sErr);

		ConsoleWrite(iFd, sReply);
		return;
	}

	ConsoleWrite(iFd, "ok\n");
}

#endif
//---------------------------------------------------------------------------

void PxConsoleInit() {
#ifndef _WIN32
	if(PxAdoptListenFdByName(PX_CONSOLE_FD_NAME, &g_iListenFd) == false) {
		g_iListenFd = -1;
		return;
	}

	const int iFlags = fcntl(g_iListenFd, F_GETFL, 0);

	if(iFlags != -1) {
		fcntl(g_iListenFd, F_SETFL, iFlags | O_NONBLOCK);
	}

	LogEmit(PX_LOG_NOTICE, PX_SUB_CONSOLE, "Lua console listening");
#endif
}
//---------------------------------------------------------------------------

void PxConsolePoll() {
#ifndef _WIN32
	if(g_iListenFd == -1) {
		return;
	}

	ConsoleAccept();

	const time_t tNow = time(NULL);

	for(size_t szi = 0; szi < g_szConns; ) {
		PxConsoleConn * pConn = &g_Conns[szi];

		bool bEof = false, bDrop = false;

		for(;;) {
			char sTmp[PX_CONSOLE_READ_SIZE];
			const ssize_t sszRead = recv(pConn->iFd, sTmp, sizeof(sTmp), 0);

			if(sszRead > 0) {
				if(ConnAppend(pConn, sTmp, (size_t)sszRead) == false) {
					LogEmitJournal(PX_LOG_WARNING, PX_SUB_CONSOLE,
						"Console chunk over the size limit, connection dropped");
					bDrop = true;
					break;
				}

				continue;
			}

			if(sszRead == 0) {
				bEof = true;
				break;
			}

			if(errno == EINTR) {
				continue;
			}

			if(errno == EAGAIN || errno == EWOULDBLOCK) {
				break;
			}

			bDrop = true;
			break;
		}

		if(bEof == false && bDrop == false) {
			if(tNow < pConn->tDeadline) {
				szi++;
				continue;
			}

			LogEmitJournal(PX_LOG_WARNING, PX_SUB_CONSOLE,
				"Console connection sent no end of input in time, dropped");
			bDrop = true;
		}

		char * sChunk = bDrop == false ? pConn->sBuf : NULL;
		const size_t szChunk = bDrop == false ? pConn->szLen : 0;

		int iFd = -1;

		if(sChunk != NULL) {
			pConn->sBuf = NULL;
			iFd = pConn->iFd;
			pConn->iFd = -1;
		}

		ConnDrop(szi);

		if(sChunk != NULL) {
			if(szChunk != 0) {
				ConsoleDispatch(iFd, sChunk, szChunk);
			}

			close(iFd);
			free(sChunk);
		}
	}
#endif
}
//---------------------------------------------------------------------------

void PxConsoleClose() {
#ifndef _WIN32
	while(g_szConns > 0) {
		ConnDrop(g_szConns - 1);
	}

	if(g_iListenFd != -1) {
		close(g_iListenFd);
		g_iListenFd = -1;
	}
#endif
}
//---------------------------------------------------------------------------
