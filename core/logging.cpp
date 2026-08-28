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
#include "logging.h"
#include "ServerManager.h"
#include "sdjournal.h"
#include "SettingManager.h"
//---------------------------------------------------------------------------

static const size_t PX_LOG_BUFSIZE = 4096;

enum LogStream { PX_STREAM_SYSTEM, PX_STREAM_SCRIPT, PX_STREAM_DEBUG, PX_STREAM_COUNT };

static pthread_mutex_t g_mtxLog = PTHREAD_MUTEX_INITIALIZER;
static FILE * g_pFiles[PX_STREAM_COUNT] = { NULL, NULL, NULL };
static bool g_bOpenFailed[PX_STREAM_COUNT] = { false, false, false };

static const char * g_sStreamFile[PX_STREAM_COUNT] = {
	"logs" PX_DIRSEP "system.log",
	"logs" PX_DIRSEP "script.log",
	"logs" PX_DIRSEP "debug.log"
};

static int g_iJournal = -1;

static void WriteStderr(const int iPriority, const char * sSubsystem, const char * sMsg);
//---------------------------------------------------------------------------

static bool UsingJournal() {
	if(g_iJournal != -1) {
		return g_iJournal == 1;
	}

	g_iJournal = 0;

#ifndef _WIN32
	const char * sStream = getenv("JOURNAL_STREAM");
	if(sStream != NULL) {
		unsigned long ulDev = 0, ulIno = 0;
		if(sscanf(sStream, "%lu:%lu", &ulDev, &ulIno) == 2) {
			struct stat st;
			if(fstat(STDERR_FILENO, &st) == 0 &&
				(unsigned long)st.st_dev == ulDev && (unsigned long)st.st_ino == ulIno) {
				g_iJournal = 1;
			}
		}
	}
#endif

	return g_iJournal == 1;
}
//---------------------------------------------------------------------------

static LogStream StreamFor(const char * sSubsystem) {
	if(strcmp(sSubsystem, PX_SUB_SCRIPT) == 0) {
		return PX_STREAM_SCRIPT;
	} else if(strcmp(sSubsystem, PX_SUB_DEBUG) == 0) {
		return PX_STREAM_DEBUG;
	}

	return PX_STREAM_SYSTEM;
}
//---------------------------------------------------------------------------

static FILE * FileFor(const LogStream eStream) {
	if(g_pFiles[eStream] != NULL) {
		return g_pFiles[eStream];
	}

	if(g_bOpenFailed[eStream] == true || ServerManager::m_sPath.size() == 0) {
		return NULL;
	}

	// the [MEM] callers reach this under allocation failure, so no string concat here
	char sPath[PATH_MAX];
	if(snprintf(sPath, sizeof(sPath), "%s" PX_DIRSEP "%s", ServerManager::m_sPath.c_str(),
		g_sStreamFile[eStream]) >= (int)sizeof(sPath)) {
		g_bOpenFailed[eStream] = true;
		return NULL;
	}

	g_pFiles[eStream] = fopen(sPath, "a");

	if(g_pFiles[eStream] == NULL) {
		g_bOpenFailed[eStream] = true;

		char sErr[256];
		snprintf(sErr, sizeof(sErr), "cannot open %s: %s", g_sStreamFile[eStream], strerror(errno));
		WriteStderr(PX_LOG_WARNING, PX_SUB_HUB, sErr);

		return NULL;
	}

	return g_pFiles[eStream];
}
//---------------------------------------------------------------------------

static void FormatTime(char * sBuf, const size_t szSize) {
	time_t tmNow;
	time(&tmNow);

#ifdef _WIN32
	struct tm * ptmLocal = localtime(&tmNow);
#else
	struct tm tmLocal;
	struct tm * ptmLocal = localtime_r(&tmNow, &tmLocal);
#endif

	if(ptmLocal == NULL || strftime(sBuf, szSize, "%Y-%m-%dT%H:%M:%S%z", ptmLocal) == 0) {
		sBuf[0] = '\0';
	}
}
//---------------------------------------------------------------------------

static void WriteStderr(const int iPriority, const char * sSubsystem, const char * sMsg) {
	const char * sLine = sMsg;

	// journald applies the prefix per line
	while(sLine != NULL && *sLine != '\0') {
		const char * sEnd = strchr(sLine, '\n');
		const int iLen = (sEnd != NULL) ? (int)(sEnd - sLine) : (int)strlen(sLine);

		if(iLen > 0) {
			if(UsingJournal() == true) {
				fprintf(stderr, "<%d>%s: %.*s\n", iPriority, sSubsystem, iLen, sLine);
			} else {
				char sTime[32];
				FormatTime(sTime, sizeof(sTime));
				fprintf(stderr, "%s [%d] %s: %.*s\n", sTime, iPriority, sSubsystem, iLen, sLine);
			}
		}

		sLine = (sEnd != NULL) ? sEnd + 1 : NULL;
	}
}
//---------------------------------------------------------------------------

static void WriteFile(const int iPriority, const char * sSubsystem, const char * sMsg) {
	const LogStream eStream = StreamFor(sSubsystem);

	if(eStream == PX_STREAM_SCRIPT && SettingManager::m_Ptr != NULL &&
		SettingManager::m_Ptr->m_bBools[SETBOOL_LOG_SCRIPT_ERRORS] == false) {
		return;
	}

	FILE * fw = FileFor(eStream);
	if(fw == NULL) {
		return;
	}

	char sTime[32];
	FormatTime(sTime, sizeof(sTime));

	// stamp every line, a continuation line without one cannot be parsed back out
	const char * sLine = sMsg;

	while(sLine != NULL && *sLine != '\0') {
		const char * sEnd = strchr(sLine, '\n');
		const int iLen = (sEnd != NULL) ? (int)(sEnd - sLine) : (int)strlen(sLine);

		if(iLen > 0) {
			fprintf(fw, "%s [%d] %.*s\n", sTime, iPriority, iLen, sLine);
		}

		sLine = (sEnd != NULL) ? sEnd + 1 : NULL;
	}

	fflush(fw);
}
//---------------------------------------------------------------------------

void LogEmit(const int iPriority, const char * sSubsystem, const char * sMsg) {
	if(sMsg == NULL || *sMsg == '\0') {
		return;
	}

	char sBuf[PX_LOG_BUFSIZE];
	size_t szLen = strlen(sMsg);

	if(szLen >= sizeof(sBuf)) {
		szLen = sizeof(sBuf) - 1;
	}

	while(szLen > 0 && (sMsg[szLen - 1] == '\n' || sMsg[szLen - 1] == '\r')) {
		szLen--;
	}

	if(szLen == 0) {
		return;
	}

	memcpy(sBuf, sMsg, szLen);
	sBuf[szLen] = '\0';

	pthread_mutex_lock(&g_mtxLog);
	WriteStderr(iPriority, sSubsystem, sBuf);
	WriteFile(iPriority, sSubsystem, sBuf);
	pthread_mutex_unlock(&g_mtxLog);
}
//---------------------------------------------------------------------------

void LogEmitNoAlloc(const int iPriority, const char * sSubsystem, const char * sMsg) {
	LogEmit(iPriority, sSubsystem, sMsg);
}
//---------------------------------------------------------------------------

void LogEmitField(const int iPriority, const char * sSubsystem, const char * sField,
	const char * sValue, const char * sMsg) {
	if(sMsg == NULL || *sMsg == '\0') {
		return;
	}

	// the file sink has no fields, so the value goes into the text
	char sBuf[PX_LOG_BUFSIZE];
	if(snprintf(sBuf, sizeof(sBuf), "%s: %s", sValue != NULL ? sValue : "?", sMsg) <= 0) {
		return;
	}

	size_t szLen = strlen(sBuf);
	while(szLen > 0 && (sBuf[szLen - 1] == '\n' || sBuf[szLen - 1] == '\r')) {
		sBuf[--szLen] = '\0';
	}

	if(szLen == 0) {
		return;
	}

	pthread_mutex_lock(&g_mtxLog);

	// the socket exists on any systemd host, so its presence is not the test
	// JournalSocket() caches its probe, so the send is under the same lock
	if(UsingJournal() == false ||
		PxJournalSend(iPriority, sSubsystem, sMsg, sField, sValue) == false) {
		WriteStderr(iPriority, sSubsystem, sBuf);
	}

	WriteFile(iPriority, sSubsystem, sBuf);

	pthread_mutex_unlock(&g_mtxLog);
}
//---------------------------------------------------------------------------

void LogEmitFormat(const int iPriority, const char * sSubsystem, const char * sFormat, ...) {
	char sBuf[PX_LOG_BUFSIZE];

	va_list vlArgs;
	va_start(vlArgs, sFormat);
	const int iLen = vsnprintf(sBuf, sizeof(sBuf), sFormat, vlArgs);
	va_end(vlArgs);

	if(iLen <= 0) {
		return;
	}

	LogEmit(iPriority, sSubsystem, sBuf);
}
//---------------------------------------------------------------------------

void LogReopenFiles() {
	pthread_mutex_lock(&g_mtxLog);

	for(size_t szi = 0; szi < PX_STREAM_COUNT; szi++) {
		if(g_pFiles[szi] != NULL) {
			fclose(g_pFiles[szi]);
			g_pFiles[szi] = NULL;
		}

		g_bOpenFailed[szi] = false;
	}

	pthread_mutex_unlock(&g_mtxLog);
}
//---------------------------------------------------------------------------

void LogClose() {
	LogReopenFiles();
}
//---------------------------------------------------------------------------
