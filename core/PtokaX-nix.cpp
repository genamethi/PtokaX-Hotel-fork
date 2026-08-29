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
#include "eventqueue.h"
#include "GlobalDataQueue.h"
#include "LanguageManager.h"
#include "logging.h"
#include "LuaConsole.h"
#include "LuaScriptManager.h"
#include "sdlisten.h"
#include "sdnotify.h"
#include "ServerManager.h"
#include "ServerThread.h"
#include "serviceLoop.h"
#include "SettingManager.h"
#include "utility.h"
//---------------------------------------------------------------------------
static bool bTerminatedBySignal = false;
static int iSignal = 0;
static volatile sig_atomic_t bReloadRequested = 0;
static volatile sig_atomic_t bReopenRequested = 0;
//---------------------------------------------------------------------------

static void ReloadSigHandler(int /*iSig*/) {
	bReloadRequested = 1;
}
//---------------------------------------------------------------------------

static void ReopenSigHandler(int /*iSig*/) {
	bReopenRequested = 1;
}
//---------------------------------------------------------------------------

static void SigHandler(int iSig) {
    bTerminatedBySignal = true;

    iSignal = iSig;

	// restore to default...
	struct sigaction sigact;
	sigact.sa_handler = SIG_DFL;
	sigemptyset(&sigact.sa_mask);
	sigact.sa_flags = 0;
	    
	sigaction(iSig, &sigact, NULL);
}
//---------------------------------------------------------------------------

static void Usage(FILE * fOut) {
	fprintf(fOut, "Usage: PtokaX [-v] [-m] [-c configdir]\n\n"
		"Options:\n"
		"\t-c configdir\t- absolute path to PtokaX configuration directory.\n"
		"\t-v\t\t- show PtokaX version with build date and time.\n"
		"\t-m\t\t- show PtokaX configuration menu.\n"
		"\t-h\t\t- show this help.\n"
	);
}
//---------------------------------------------------------------------------

int main(int argc, char* argv[]) {
	PxListenFdsInit();

	bool bSetup = false;

	for(int i = 1; i < argc; i++) {
	    if(strcasecmp(argv[i], "-c") == 0) {
	    	if(++i == argc) {
	            fprintf(stderr, "Missing config directory!\n");
	            return EXIT_FAILURE;
	    	}

			if(argv[i][0] != '/') {
	            fprintf(stderr, "Config directory must be absolute path!\n");
	            return EXIT_FAILURE;
			}
	
	        size_t szLen = strlen(argv[i]);
			if(argv[i][szLen - 1] == '/') {
	            ServerManager::m_sPath = string(argv[i], szLen - 1);
			} else {
	            ServerManager::m_sPath = string(argv[i], szLen);
	        }
	
	        if(DirExist(ServerManager::m_sPath.c_str()) == false) {
	        	if(mkdir(ServerManager::m_sPath.c_str(), 0755) == -1) {
	                fprintf(stderr, "Config directory not exist and can't be created!\n");
	            }
            }
	    } else if(strcasecmp(argv[i], "-v") == 0 || strcasecmp(argv[i], "--version") == 0) {
	        printf("%s built on %s %s\n", g_sPtokaXTitle, __DATE__, __TIME__);
	        return EXIT_SUCCESS;
	    } else if(strcasecmp(argv[i], "-h") == 0 || strcasecmp(argv[i], "--help") == 0) {
	        Usage(stdout);
	        return EXIT_SUCCESS;
	    } else if(strcasecmp(argv[i], "/generatexmllanguage") == 0) {
	        LanguageManager::GenerateXmlExample();
	        return EXIT_SUCCESS;
	    } else if(strcasecmp(argv[i], "-m") == 0) {
	    	bSetup = true;
	    } else {
	    	fprintf(stderr, "Unknown parameter %s.\n", argv[i]);
	    	Usage(stderr);
	    	return EXIT_FAILURE;
		}
	}
	
	if(ServerManager::m_sPath.size() == 0) {
	    char curdir[PATH_MAX];
	    if(getcwd(curdir, PATH_MAX) != NULL) {
	        ServerManager::m_sPath = curdir;
	    } else {
	        ServerManager::m_sPath = ".";
	    }
	}

	if(bSetup == true) {
		ServerManager::Initialize();

		ServerManager::CommandLineSetup();
		
		ServerManager::FinalClose();

		LogClose();

		return EXIT_SUCCESS;
	}

	sigset_t sst;
	sigemptyset(&sst);
	sigaddset(&sst, SIGPIPE);
	sigaddset(&sst, SIGURG);
	sigaddset(&sst, SIGALRM);

	pthread_sigmask(SIG_BLOCK, &sst, NULL);
	
	struct sigaction sigact;
	sigact.sa_handler = SigHandler;
	sigemptyset(&sigact.sa_mask);
	sigact.sa_flags = 0;
	
	if(sigaction(SIGINT, &sigact, NULL) == -1) {
	    AppendDebugLog("%s - [ERR] Cannot create sigaction SIGINT in main\n");
	    exit(EXIT_FAILURE);
	}
	
	if(sigaction(SIGTERM, &sigact, NULL) == -1) {
	    AppendDebugLog("%s - [ERR] Cannot create sigaction SIGTERM in main\n");
	    exit(EXIT_FAILURE);
	}
	
	if(sigaction(SIGQUIT, &sigact, NULL) == -1) {
	    AppendDebugLog("%s - [ERR] Cannot create sigaction SIGQUIT in main\n");
	    exit(EXIT_FAILURE);
	}
	
	struct sigaction sigreload;
	sigreload.sa_handler = ReloadSigHandler;
	sigemptyset(&sigreload.sa_mask);
	sigreload.sa_flags = SA_RESTART;

	if(sigaction(SIGHUP, &sigreload, NULL) == -1) {
	    AppendDebugLog("%s - [ERR] Cannot create sigaction SIGHUP in main\n");
	    exit(EXIT_FAILURE);
	}

	struct sigaction sigreopen;
	sigreopen.sa_handler = ReopenSigHandler;
	sigemptyset(&sigreopen.sa_mask);
	sigreopen.sa_flags = SA_RESTART;

	if(sigaction(SIGUSR1, &sigreopen, NULL) == -1) {
	    AppendDebugLog("%s - [ERR] Cannot create sigaction SIGUSR1 in main\n");
	    exit(EXIT_FAILURE);
	}

	ServerManager::Initialize();

	if(ServerManager::Start() == false) {
		LogEmit(PX_LOG_ERR, PX_SUB_HUB, "Server start failed!");
		LogClose();
		return EXIT_FAILURE;
	}

	LogEmitFormat(PX_LOG_INFO, PX_SUB_HUB, "%s running", g_sPtokaXTitle);

	PxConsoleInit();

	PxReportUnclaimedFds();

	{
		char sPorts[128];
		size_t szPos = 0;
		uint16_t ui16Last = 0, ui16Bound = 0, ui16Wanted = 0;

		while(ui16Wanted < 25 && SettingManager::m_Ptr->m_ui16PortNumbers[ui16Wanted] != 0) {
			ui16Wanted++;
		}

		// only listeners that bound are on this list, so it cannot claim a dead port
		for(ServerThread * pCur = ServerManager::m_pServersS; pCur != NULL; pCur = pCur->m_pNext) {
			if(pCur->m_ui16Port == ui16Last) {
				continue;
			}

			ui16Last = pCur->m_ui16Port;
			ui16Bound++;

			const int iLen = snprintf(sPorts + szPos, sizeof(sPorts) - szPos, szPos == 0 ? "%hu" : ", %hu", ui16Last);

			if(iLen <= 0 || (size_t)iLen >= sizeof(sPorts) - szPos) {
				break;
			}

			szPos += (size_t)iLen;
		}

		if(ui16Bound < ui16Wanted) {
			LogEmitFormat(PX_LOG_WARNING, PX_SUB_HUB, "Only %hu of %hu configured ports are listening: %s",
				ui16Bound, ui16Wanted, sPorts);
		}

		PxNotifyFormat("READY=1\nSTATUS=Listening on %s", sPorts);
	}
	
	struct timespec sleeptime;
	sleeptime.tv_sec = 0;
	sleeptime.tv_nsec = 100000000;
	
	while(true) {
		ServiceLoop::m_Ptr->Looper();

		if(ServerManager::m_bServerTerminated == true) {
		    break;
		}

		if(bReloadRequested != 0) {
			bReloadRequested = 0;

			struct timespec tsNow;
			clock_gettime(CLOCK_MONOTONIC, &tsNow);
			PxNotifyFormat("RELOADING=1\nMONOTONIC_USEC=%" PRIu64,
				(uint64_t)((uint64_t)tsNow.tv_sec * 1000000ULL + (uint64_t)(tsNow.tv_nsec / 1000)));

			ScriptManager::m_Ptr->Restart();

			LogEmit(PX_LOG_NOTICE, PX_SUB_HUB, "Scripts restarted");

			PxNotify("READY=1");
		}

		if(bReopenRequested != 0) {
			bReopenRequested = 0;

			LogReopenFiles();
		}

	    if(bTerminatedBySignal == true) {
	        if(ServerManager::m_bIsClose == true) {
	            break;
	        }
	
	        string str("Received signal ");
	
	        if(iSignal == SIGINT) {
	            str += "SIGINT";
	        } else if(iSignal == SIGTERM) {
	            str += "SIGTERM";
	        } else if(iSignal == SIGQUIT) {
	            str += "SIGQUIT";
	        } else if(iSignal == SIGHUP) {
	            str += "SIGHUP";
	        } else {
	            str += string(iSignal);
	        }
	
	        str += " ending...";
	
	        AppendLog(str.c_str());

	        PxNotify("STOPPING=1\nSTATUS=Saving configuration...");

	        ServerManager::m_bIsClose = true;
	        ServerManager::Stop();
	
	        // tell the scripts about the end
	        ScriptManager::m_Ptr->OnExit();
	
	        // send last possible global data
	        GlobalDataQueue::m_Ptr->SendFinalQueue();
	
	        ServerManager::FinalStop(true);
	
	        break;
	    }
	
	    nanosleep(&sleeptime, NULL);
	}

	PxConsoleClose();

	LogEmitFormat(PX_LOG_INFO, PX_SUB_HUB, "%s ending", g_sPtokaXTitle);

	LogClose();

    return EXIT_SUCCESS;
}
//---------------------------------------------------------------------------
