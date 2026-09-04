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
#include "PingerInfo.h"

#include "LanguageManager.h"
#include "ServerManager.h"
#include "SettingManager.h"
#include "utility.h"
//---------------------------------------------------------------------------

static void PingerAppendJsonString(std::string &sOut, const char * sValue) {
	sOut += "\"";

	if(sValue == NULL) {
		sOut += "\"";
		return;
	}

	for(const char * p = sValue; *p != '\0'; p++) {
		const unsigned char uc = (unsigned char)*p;

		switch(uc) {
			case '"': sOut += "\\\""; break;
			case '\\': sOut += "\\\\"; break;
			case '\b': sOut += "\\b"; break;
			case '\f': sOut += "\\f"; break;
			case '\n': sOut += "\\n"; break;
			case '\r': sOut += "\\r"; break;
			case '\t': sOut += "\\t"; break;
			default:
				if(uc < 0x20) {
					char sEsc[7];
					snprintf(sEsc, sizeof(sEsc), "\\u%04x", uc);
					sOut += sEsc;
				} else {
					sOut += *p;
				}
		}
	}

	sOut += "\"";
}
//---------------------------------------------------------------------------

// ping.md wants MB rounded up, PtokaX counts bytes
static uint64_t PingerToMegabytes(const uint64_t ui64Bytes) {
	return (ui64Bytes + 1048575) / 1048576;
}
//---------------------------------------------------------------------------

static uint64_t PingerMinShareMegabytes() {
	const int16_t i16Limit = SettingManager::m_Ptr->m_i16Shorts[SETSHORT_MIN_SHARE_LIMIT];

	if(i16Limit <= 0) {
		return 0;
	}

	// units are the index into B, kB, MB, GB, TB
	uint64_t ui64Bytes = (uint64_t)i16Limit;

	for(int16_t i16i = 0; i16i < SettingManager::m_Ptr->m_i16Shorts[SETSHORT_MIN_SHARE_UNITS]; i16i++) {
		ui64Bytes *= 1024;
	}

	return PingerToMegabytes(ui64Bytes);
}
//---------------------------------------------------------------------------

void PingerWriteInfo() {
	const char * sAddresses = SettingManager::m_Ptr->m_sTexts[SETTXT_PINGER_ADDRESSES];

	if(sAddresses == NULL || sAddresses[0] == '\0') {
		return;
	}

	std::string sJson;
	sJson.reserve(1024);

	sJson += "{\n  \"name\": ";
	PingerAppendJsonString(sJson, SettingManager::m_Ptr->m_sTexts[SETTXT_HUB_NAME]);

	sJson += ",\n  \"desc\": ";
	PingerAppendJsonString(sJson, SettingManager::m_Ptr->m_sTexts[SETTXT_HUB_DESCRIPTION]);

	sJson += ",\n  \"addr\": [";

	const char * sStart = sAddresses;
	bool bFirst = true;

	while(true) {
		const char * sEnd = strchr(sStart, ';');
		const size_t szLen = sEnd != NULL ? (size_t)(sEnd - sStart) : strlen(sStart);

		if(szLen != 0) {
			const std::string sOne(sStart, szLen);

			sJson += bFirst == true ? "\n    " : ",\n    ";
			PingerAppendJsonString(sJson, sOne.c_str());

			bFirst = false;
		}

		if(sEnd == NULL) {
			break;
		}

		sStart = sEnd + 1;
	}

	sJson += bFirst == true ? "]" : "\n  ]";

	const char * sEmail = SettingManager::m_Ptr->m_sTexts[SETTXT_HUB_OWNER_EMAIL];

	if(sEmail != NULL && sEmail[0] != '\0') {
		sJson += ",\n  \"email\": ";
		PingerAppendJsonString(sJson, sEmail);
	}

	char sNumbers[512];

	time_t tNow;
	time(&tNow);

	const int iLen = snprintf(sNumbers, sizeof(sNumbers),
		",\n  \"users\": {\n    \"cur\": %u,\n    \"max\": %hd,\n    \"top\": %u\n  }"
		",\n  \"share\": {\n    \"cur\": %" PRIu64 ",\n    \"min\": %" PRIu64 ",\n    \"top\": %" PRIu64 "\n  }"
		",\n  \"uptime\": %" PRId64 ",\n  \"encoding\": ",
		ServerManager::m_ui32Logged,
		SettingManager::m_Ptr->m_i16Shorts[SETSHORT_MAX_USERS],
		ServerManager::m_ui32Peak,
		PingerToMegabytes(ServerManager::m_ui64TotalShare),
		PingerMinShareMegabytes(),
		PingerToMegabytes(ServerManager::m_ui64TotalShare),
		(int64_t)(tNow - ServerManager::m_tStartTime));

	if(iLen < 0 || (size_t)iLen >= sizeof(sNumbers)) {
		return;
	}

	sJson += sNumbers;

	const char * sEncoding = SettingManager::m_Ptr->m_sTexts[SETTXT_ENCODING];
	PingerAppendJsonString(sJson, sEncoding != NULL && sEncoding[0] != '\0' ? sEncoding : "utf-8");

	sJson += "\n}\n";

	// written whole then renamed, so a pinger never reads a half-written file
	const std::string sFinal = std::string(ServerManager::m_sPath.c_str()) + "/hubinfo.json";
	const std::string sTemp = sFinal + ".tmp";

	FILE * f = fopen(sTemp.c_str(), "wb");

	if(f == NULL) {
		return;
	}

	const bool bWritten = fwrite(sJson.c_str(), 1, sJson.size(), f) == sJson.size();

	fclose(f);

	if(bWritten == false) {
		remove(sTemp.c_str());
		return;
	}

	if(rename(sTemp.c_str(), sFinal.c_str()) != 0) {
		remove(sTemp.c_str());
	}
}
//---------------------------------------------------------------------------
