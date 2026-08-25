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
#ifndef loggingH
#define loggingH
//---------------------------------------------------------------------------

// syslog(3) values - journald reads them from a leading "<N>"
enum LogPriority {
	PX_LOG_ERR = 3,
	PX_LOG_WARNING = 4,
	PX_LOG_NOTICE = 5,
	PX_LOG_INFO = 6,
	PX_LOG_DEBUG = 7
};

#define PX_SUB_HUB     "hub"
#define PX_SUB_SCRIPT  "script"
#define PX_SUB_DEBUG   "debug"

void LogEmit(const int iPriority, const char * sSubsystem, const char * sMsg);

void LogEmitFormat(const int iPriority, const char * sSubsystem, const char * sFormat, ...)
#ifdef __GNUC__
	__attribute__((format(printf, 3, 4)))
#endif
;

// never allocates
void LogEmitNoAlloc(const int iPriority, const char * sSubsystem, const char * sMsg);

// adds one journal field; falls back to LogEmit with the value folded into the text
void LogEmitField(const int iPriority, const char * sSubsystem, const char * sField,
	const char * sValue, const char * sMsg);

void LogReopenFiles();
void LogClose();

//---------------------------------------------------------------------------
#endif
