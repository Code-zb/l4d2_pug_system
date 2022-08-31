#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <confogl>
#undef REQUIRE_PLUGIN
#include <readyup>
#include <pause>



Handle hMaxPlayers;
bool ReadyUpLoaded;
bool bRQDeclared;

bool bWaitFirstReadyUp = true;

int iPrevButtons[MAXPLAYERS + 1];
int iPrevMouse[MAXPLAYERS + 1][2];
int iLastActivity[MAXPLAYERS + 1];

int bResponsibleForPause[8]; //parallel with arPlayersAll[]
int iLastUnpause;
bool bPrinted[8]; //parallel with arPlayersAll[]
int iSingleAbsence[8]; //parallel with arPlayersAll[]

char sAuthKey[40];
bool bIsL4D2Center;
char sPublicIP[32];
bool bPublicIP;
int iMaxSpecs;

//GameInfo
int iServerReserved = -1; //-1 - not checked, 0 - not reserved, 1 - reserved
char arPlayersA[4][20];
char arPlayersB[4][20];
char arPlayersAll[8][20];
char sConfoglConfig[32];
char sFirstMap[128];
char sLastMap[128];
int iMinMmr = -2000000000;
int iMaxMmr = 2000000000;
char sGameState[32];
int iMaxAbsent = 420;
int iMaxSingleAbsent = 240;

//Game results
int iSettledScores[2];
char sDominator[2][20];
char sInferior[2][20];
bool bTankKilled;
bool bInRound;
bool bInMapTransition;
int iMapsFinished;
int iAbsenceCounter[8]; //parallel with arPlayersAll[]
bool bGameEnded;
bool bGameFinished;



public OnPluginStart() {
	if (GetConVarInt(CreateConVar("sm_bansystem_enabled", "0", "0 - disabled, 1 - Safehouse, 2 - Santa Clouds, 3 - Liberty, 4 - l4d2center")) == 4) {
		bIsL4D2Center = true;
		GetConVarString(CreateConVar("l4d2center_auth_key", "none"), sAuthKey, sizeof(sAuthKey));
		hMaxPlayers = FindConVar("sv_maxplayers");
		ReadyUpLoaded = LibraryExists("readyup");
		CreateTimer(10.0, Timer_UpdateGameState, 0, TIMER_REPEAT);
		HookEvent("round_end", Event_RoundEnd);
		HookEvent("player_team", Event_PlayerTeam);

		//AFK
		AddCommandListener(OnCommandExecute, "spec_mode");
		AddCommandListener(OnCommandExecute, "spec_next");
		AddCommandListener(OnCommandExecute, "spec_prev");
		AddCommandListener(OnCommandExecute, "say");
		AddCommandListener(OnCommandExecute, "say_team");
		AddCommandListener(OnCallVote, "callvote");
		RegConsoleCmd("sm_ready", Ready_Cmd);
		RegConsoleCmd("sm_r", Ready_Cmd);
		CreateTimer(1.0, Timer_CountAbsence, 0, TIMER_REPEAT);
		CreateTimer(0.9876, Timer_AutoTeam, 0, TIMER_REPEAT);

		//admit RQ
		RegConsoleCmd("sm_rq", Ragequit_Cmd);
		RegConsoleCmd("sm_ragequit", Ragequit_Cmd);
		RegConsoleCmd("sm_quit", Ragequit_Cmd);

		//Test
		//RegAdminCmd("sm_test", Cmd_Test, 0);
	}
}

public void OnLibraryAdded(const char[] name) {
	ReadyUpLoaded = LibraryExists("readyup");
}

public void OnLibraryRemoved(const char[] name) {
	ReadyUpLoaded = LibraryExists("readyup");
}

public Action Ragequit_Cmd(int client, int args) {
	if (!bWaitFirstReadyUp && !bRQDeclared && client > 0 && IsClientConnected(client) && !IsFakeClient(client)) {
		int iPlayer = GetClientLobbyParticipant(client);
		if (iPlayer != -1) {
			bRQDeclared = true;
			iAbsenceCounter[iPlayer] = iMaxAbsent;
			CreateTimer(0.2, UpdateGameResults);
		}
	}
	return Plugin_Handled;
}

//Test
/*Action Cmd_Test(int client, int args) {
	CreateTimer(0.0, UpdateGameResults);
	return Plugin_Handled;
}*/

public Action Timer_AutoTeam(Handle timer) {
	if (iServerReserved == 1) {
		bool bSomeoneSpecced;
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) > 1) {
				if (GetClientLobbyParticipant(i) == -1) {
					FakeClientCommand(i, "sm_s");
					bSomeoneSpecced = true;
				} else if (GetClientLobbyParticipant(i) != -1 && GetClientTeam(i) != GetPlayerCorrectTeam(i)) {
					FakeClientCommand(i, "sm_s");
					bSomeoneSpecced = true;
				}
			}
		}
		if (bSomeoneSpecced) {
			return Plugin_Continue;
		}

		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 1 && GetClientLobbyParticipant(i) != -1) {
				FakeClientCommand(i, "jointeam %d", GetPlayerCorrectTeam(i));
				return Plugin_Continue;
			}
		}
	}

	return Plugin_Continue;
}

public Action Timer_UpdateGameState(Handle timer) {
	if (!bPublicIP) {
		int arIPaddr[4];
		if (SteamWorks_GetPublicIP(arIPaddr)) {
			Format(sPublicIP, sizeof(sPublicIP), "%d.%d.%d.%d:%d", arIPaddr[0], arIPaddr[1], arIPaddr[2], arIPaddr[3], GetConVarInt(FindConVar("hostport")));
			bPublicIP = true;
		}
		if (!bPublicIP) {
			return Plugin_Continue;
		}
	}

	char sUrl[256];
	Format(sUrl, sizeof(sUrl), "https://api.l4d2center.com/gs/getgame?auth_key=%s", sAuthKey);
	Handle hSWReq = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sUrl);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hSWReq, 9);
	SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(hSWReq, 10000);
	SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(hSWReq, false);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "auth_key", sAuthKey);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "ip", sPublicIP);
	SteamWorks_SetHTTPCallbacks(hSWReq, SWReqCompleted_GameInfo);
	SteamWorks_SendHTTPRequest(hSWReq);
	return Plugin_Continue;
}

public OnRoundIsLive() {
	if (bIsL4D2Center) {
		bInRound = true;
		bInMapTransition = false;
		bTankKilled = false;
		iLastUnpause = GetTime();
		if (bWaitFirstReadyUp) {
			bWaitFirstReadyUp = false;
			SendFullReady();
		}
	}
}

public Action GameInfoReceived(Handle timer) {
	if (iServerReserved == 1) {

		//Maximum sv_maxplayers-8 spectators allowed
		int iCurMaxSpecs = GetConVarInt(hMaxPlayers) - 8;
		if (iCurMaxSpecs < iMaxSpecs) {
			int iCurSpecs;
			for (int i = 1; i <= MaxClients; i++) {
				if (IsClientConnected(i) && !IsFakeClient(i) && GetClientLobbyParticipant(i) == -1) {
					iCurSpecs++;
				}
			}
			if (iCurSpecs > iCurMaxSpecs) {
				for (int i = 1; i <= MaxClients; i++) {
					if (IsClientConnected(i) && !IsFakeClient(i) && GetClientLobbyParticipant(i) == -1) {
						KickClient(i, "The players have limited slots for spectators");
					}
				}
			}
		}
		iMaxSpecs = iCurMaxSpecs;

		//Autostart Confogl
		if (!LGO_IsMatchModeLoaded()) {
			for (int i = 1; i <= MaxClients; i++) {
				if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) > 1) {
					//PrintToChatAll("sm_forcematch %s %s", sConfoglConfig, sFirstMap);
					ServerCommand("sm_forcematch %s %s", sConfoglConfig, sFirstMap);
					break;
				}
			}
		}


		if (StrEqual(sGameState, "readyup_expired")) {
			CreateTimer(1.0, SendReadyPlayers);
		} else if (StrEqual(sGameState, "game_proceeds")) {
			if (bWaitFirstReadyUp) {
				//Server crashed, do smth
				for (int i = 1; i <= MaxClients; i++) {
					if (IsClientConnected(i) && !IsFakeClient(i)) {
						KickClient(i, "The server crashed midgame. Its not possible to continue playing. Go back on the site and join a new game");
					}
				}
			} else {
				CreateTimer(1.0, UpdateGameResults);
			}
		}


	} else if (iServerReserved == 0) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientConnected(i) && !IsFakeClient(i)) {
				KickClient(i, "This server is reserved for l4d2center.com lobbies");
			}
		}
	}
	return Plugin_Continue;
}

public Action UpdateGameResults(Handle timer) {

	//Check if players left
	bool bClientsConnected;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientConnected(i) && !IsFakeClient(i)) {
			bClientsConnected = true;
			break;
		}
	}
	int iPlayers;
	if (bClientsConnected) {
		for (int i = 0; i < 8; i++) {
			int client = GetClientBySteamID64(arPlayersAll[i]);
			if (client > 0) {
				iPlayers++;
			} else if (arPlayersAll[i][0] != '7') { //count fake players, for testing purposes
				iPlayers++;
			}
		}
	}

	char sUrl[256];
	Format(sUrl, sizeof(sUrl), "https://api.l4d2center.com/gs/gameresults?auth_key=%s", sAuthKey);
	Handle hSWReq = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sUrl);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hSWReq, 9);
	SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(hSWReq, 10000);
	SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(hSWReq, false);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "auth_key", sAuthKey);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "ip", sPublicIP);

	char sBuffer[64];
	Format(sBuffer, sizeof(sBuffer), "%d", iSettledScores[0]);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "settled_scores_a", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%d", iSettledScores[1]);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "settled_scores_b", sBuffer);
	if (bInRound) {
		Format(sBuffer, sizeof(sBuffer), "%d", GameRules_GetProp("m_iCampaignScore", 4, 0) + GameRules_GetProp("m_iSurvivorScore", 4, 0));
	} else {
		Format(sBuffer, sizeof(sBuffer), "%d", GameRules_GetProp("m_iCampaignScore", 4, 0));
	}
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "current_scores_a", sBuffer);
	if (bInRound) {
		Format(sBuffer, sizeof(sBuffer), "%d", GameRules_GetProp("m_iCampaignScore", 4, 1) + GameRules_GetProp("m_iSurvivorScore", 4, 1));
	} else {
		Format(sBuffer, sizeof(sBuffer), "%d", GameRules_GetProp("m_iCampaignScore", 4, 1));
	}
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "current_scores_b", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", bInRound ? "yes" : "no");
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "in_round", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%d", GameRules_GetProp("m_bInSecondHalfOfRound", 1, 0) == 1 ? 2 : 1);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "half", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", GameRules_GetProp("m_bAreTeamsFlipped", 1, 0) == 1 ? "yes" : "no");
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "teams_flipped", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", bTankKilled ? "yes" : "no");
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "tank_killed", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", IsTankInPlay() ? "yes" : "no");
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "tank_in_play", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", sDominator[0]);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "dominator_a", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", sDominator[1]);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "dominator_b", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", sInferior[0]);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "inferior_a", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", sInferior[1]);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "inferior_b", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", bGameFinished ? "yes" : "no");
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "game_finished", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", bInMapTransition ? "yes" : "no");
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "in_map_transition", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%s", IsLastMap() ? "yes" : "no");
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "last_map", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%d", bClientsConnected ? iPlayers : 8);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "players_connected", sBuffer);
	Format(sBuffer, sizeof(sBuffer), "%d", iMapsFinished);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "maps_finished", sBuffer);
	for (int i = 0; i < 8; i++) {
		Format(sBuffer, sizeof(sBuffer), "%d", iSingleAbsence[i] >= iMaxSingleAbsent ? iMaxAbsent : iAbsenceCounter[i]);
		SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, arPlayersAll[i], sBuffer);
	}


	SteamWorks_SetHTTPCallbacks(hSWReq, SWReqCompleted_UploadResults);
	SteamWorks_SendHTTPRequest(hSWReq);




	return Plugin_Continue;
}

public void SWReqCompleted_UploadResults(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode) {
	int iBodySize;
	if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK	&& SteamWorks_GetHTTPResponseBodySize(hRequest, iBodySize) && iBodySize > 0) {
		char[] sResponse = new char[iBodySize];
		SteamWorks_GetHTTPResponseBodyData(hRequest, sResponse, iBodySize);
		PrintToServer("%s", sResponse);
		Handle kvGameInfo = CreateKeyValues("VDFresponse");
		if (StrContains(sResponse, "VDFresponse", true) > -1 && StringToKeyValues(kvGameInfo, sResponse)) {
			int iSuccess = KvGetNum(kvGameInfo, "success", -1);
			if (iSuccess) {
				int iGameEndType = KvGetNum(kvGameInfo, "game_ended_type", -1);
				if (iGameEndType == 1) {
					bGameEnded = true;
					char sWinner[3];
					if (iSettledScores[0] > iSettledScores[1]) {
						Format(sWinner, sizeof(sWinner), "A");
					} else if (iSettledScores[1] > iSettledScores[0]) {
						Format(sWinner, sizeof(sWinner), "B");
					} else {
						Format(sWinner, sizeof(sWinner), "_");
					}
					for (int i = 1; i <= MaxClients; i++) {
						if (IsClientConnected(i) && !IsFakeClient(i)) {
							KickClient(i, "Game ended: Team %s won (%d-%d)", sWinner, iSettledScores[0], iSettledScores[1]);
						}
					}
				} else if (iGameEndType == 2) {
					bGameEnded = true;
					for (int i = 1; i <= MaxClients; i++) {
						if (IsClientConnected(i) && !IsFakeClient(i)) {
							KickClient(i, "Game ended: one or more players left it midgame");
						}
					}
				} else if (iGameEndType == 3) {
					bGameEnded = true;
					for (int i = 1; i <= MaxClients; i++) {
						if (IsClientConnected(i) && !IsFakeClient(i)) {
							KickClient(i, "Game ended: players left the game");
						}
					}
				}
			}
		} else {
			PrintToChatAll("Oy oy, L4D2Center API responded with error");
			PrintToServer("Oy oy, L4D2Center API responded with error");
		}
		CloseHandle(kvGameInfo);
	} else {
		PrintToChatAll("Oy oy, L4D2Center API responded with error");
		PrintToServer("Oy oy, L4D2Center API responded with error");
	}
	CloseHandle(hRequest);
}

public Action SendReadyPlayers(Handle timer) {
	if (!bWaitFirstReadyUp) {
		SendFullReady();
		return Plugin_Continue;
	}

	int iReadyCount;
	if (ReadyUpLoaded) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) > 1 && GetClientLobbyParticipant(i) != -1 && IsReady(i)) {
				iReadyCount++;
			}
		}
	}

	char sReadyString[256];

	if (iReadyCount >= 8) {
		strcopy(sReadyString, sizeof(sReadyString), "all_ready");
	} else if (iReadyCount == 0) {
		strcopy(sReadyString, sizeof(sReadyString), "none_ready");
	} else {

		char[][] arReadyPlayers = new char[iReadyCount][20];
		int iInputIdx;
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) > 1 && GetClientLobbyParticipant(i) != -1 && IsReady(i)) {
				char SteamID64[20];
				GetClientAuthId(i, AuthId_SteamID64, SteamID64, sizeof(SteamID64), false);
				strcopy(arReadyPlayers[iInputIdx], 20, SteamID64);
				iInputIdx++;
			}
		}

		ImplodeStrings(arReadyPlayers, iReadyCount, ",", sReadyString, sizeof(sReadyString));

	}


	char sUrl[256];
	Format(sUrl, sizeof(sUrl), "https://api.l4d2center.com/gs/partialrup?auth_key=%s", sAuthKey);
	Handle hSWReq = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sUrl);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hSWReq, 9);
	SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(hSWReq, 10000);
	SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(hSWReq, false);

	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "auth_key", sAuthKey);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "ip", sPublicIP);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "ready_players", sReadyString);
	SteamWorks_SetHTTPCallbacks(hSWReq, SWReqCompleted_PartialReadyUp);
	SteamWorks_SendHTTPRequest(hSWReq);
	return Plugin_Continue;
}

public void SWReqCompleted_PartialReadyUp(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode) {
	int iBodySize;
	if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK	&& SteamWorks_GetHTTPResponseBodySize(hRequest, iBodySize) && iBodySize > 0) {
		char[] sResponse = new char[iBodySize];
		SteamWorks_GetHTTPResponseBodyData(hRequest, sResponse, iBodySize);
		PrintToServer("%s", sResponse);
		Handle kvGameInfo = CreateKeyValues("VDFresponse");
		if (StrContains(sResponse, "VDFresponse", true) > -1 && StringToKeyValues(kvGameInfo, sResponse)) {
			if (KvGetNum(kvGameInfo, "success", -1) == 1) {
				for (int i = 1; i <= MaxClients; i++) {
					if (IsClientConnected(i) && !IsFakeClient(i)) {
						KickClient(i, "Game ended: some players failed to ready up in time");
					}
				}
			}
		} else {
			PrintToChatAll("Oy oy, L4D2Center API responded with error");
			PrintToServer("Oy oy, L4D2Center API responded with error");
		}
		CloseHandle(kvGameInfo);
	} else {
		PrintToChatAll("Oy oy, L4D2Center API responded with error");
		PrintToServer("Oy oy, L4D2Center API responded with error");
	}
	CloseHandle(hRequest);
}

SendFullReady() {
	char sUrl[256];
	Format(sUrl, sizeof(sUrl), "https://api.l4d2center.com/gs/fullrup?auth_key=%s", sAuthKey);
	Handle hSWReq = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sUrl);
	SteamWorks_SetHTTPRequestNetworkActivityTimeout(hSWReq, 9);
	SteamWorks_SetHTTPRequestAbsoluteTimeoutMS(hSWReq, 10000);
	SteamWorks_SetHTTPRequestRequiresVerifiedCertificate(hSWReq, false);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "auth_key", sAuthKey);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hSWReq, "ip", sPublicIP);

	SteamWorks_SetHTTPCallbacks(hSWReq, SWReqCompleted_Dummy);
	SteamWorks_SendHTTPRequest(hSWReq);
}

public void SWReqCompleted_GameInfo(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode) {
	int iBodySize;
	if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK	&& SteamWorks_GetHTTPResponseBodySize(hRequest, iBodySize) && iBodySize > 0) {
		char[] sResponse = new char[iBodySize];
		SteamWorks_GetHTTPResponseBodyData(hRequest, sResponse, iBodySize);
		PrintToServer("%s", sResponse);
		Handle kvGameInfo = CreateKeyValues("VDFresponse");
		if (StrContains(sResponse, "VDFresponse", true) > -1 && StringToKeyValues(kvGameInfo, sResponse)) {
			iServerReserved = KvGetNum(kvGameInfo, "success", -1);
			if (iServerReserved == 1) {

				char sKeyBuffer[16];
				for (int i = 0; i < 4; i++) {
					Format(sKeyBuffer, sizeof(sKeyBuffer), "player_a%d", i);
					char sBuffer[20];
					KvGetString(kvGameInfo, sKeyBuffer, sBuffer, sizeof(sBuffer), "0");
					sBuffer[17] = '\0';
					strcopy(arPlayersA[i], 20, sBuffer);
					strcopy(arPlayersAll[i], 20, sBuffer);
				}
				for (int i = 0; i < 4; i++) {
					Format(sKeyBuffer, sizeof(sKeyBuffer), "player_b%d", i);
					char sBuffer[20];
					KvGetString(kvGameInfo, sKeyBuffer, sBuffer, sizeof(sBuffer), "0");
					sBuffer[17] = '\0';
					strcopy(arPlayersB[i], 20, sBuffer);
					strcopy(arPlayersAll[i + 4], 20, sBuffer);
				}

				KvGetString(kvGameInfo, "confogl", sConfoglConfig, sizeof(sConfoglConfig), "default");
				KvGetString(kvGameInfo, "first_map", sFirstMap, sizeof(sFirstMap), "unknown");
				KvGetString(kvGameInfo, "last_map", sLastMap, sizeof(sLastMap), "unknown");
				iMinMmr = KvGetNum(kvGameInfo, "mmr_min", -2000000000);
				iMaxMmr = KvGetNum(kvGameInfo, "mmr_max", 2000000000);
				KvGetString(kvGameInfo, "game_state", sGameState, sizeof(sGameState), "unknown");
				iMaxAbsent = KvGetNum(kvGameInfo, "max_absent", 420);
				iMaxSingleAbsent = KvGetNum(kvGameInfo, "max_single_absent", 240);

			}
			if (iServerReserved != -1) {
				CreateTimer(1.0, GameInfoReceived);
			}
		} else {
			PrintToChatAll("Oy oy, L4D2Center API responded with error");
			PrintToServer("Oy oy, L4D2Center API responded with error");
		}
		CloseHandle(kvGameInfo);
	} else {
		PrintToChatAll("Oy oy, L4D2Center API responded with error");
		PrintToServer("Oy oy, L4D2Center API responded with error");
	}
	CloseHandle(hRequest);
}

public void SWReqCompleted_Dummy(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode) {
	int iBodySize;
	if (bRequestSuccessful && eStatusCode == k_EHTTPStatusCode200OK	&& SteamWorks_GetHTTPResponseBodySize(hRequest, iBodySize) && iBodySize > 0) {
		char[] sResponse = new char[iBodySize];
		SteamWorks_GetHTTPResponseBodyData(hRequest, sResponse, iBodySize);
		PrintToServer("%s", sResponse);
		Handle kvGameInfo = CreateKeyValues("VDFresponse");
		if (StrContains(sResponse, "VDFresponse", true) > -1 && StringToKeyValues(kvGameInfo, sResponse)) {
		} else {
			PrintToChatAll("Oy oy, L4D2Center API responded with error");
			PrintToServer("Oy oy, L4D2Center API responded with error");
		}
		CloseHandle(kvGameInfo);
	} else {
		PrintToChatAll("Oy oy, L4D2Center API responded with error");
		PrintToServer("Oy oy, L4D2Center API responded with error");
	}
	CloseHandle(hRequest);
}

int GetClientLobbyParticipant(int client) {
	char sSteamID64[20];
	if (GetClientAuthId(client, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64), false)) {
		for (int i = 0; i < 8; i++) {
			if (StrEqual(arPlayersAll[i], sSteamID64)) {
				return i;
			}
		}
	}
	return -1;
}

int GetClientBySteamID64(char[] SteamID64) {
	for (int i = 1; i <= MaxClients; i++) {
		char sBuffer[20];
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientAuthId(i, AuthId_SteamID64, sBuffer, sizeof(sBuffer), false) && StrEqual(sBuffer, SteamID64)) {
			return i;
		}
	}
	return -1;
}

int GetPlayerCorrectTeam(int client) {
	char sSteamID64[20];
	if (GetClientAuthId(client, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64), false)) {
		for (int i = 0; i < 4; i++) {
			if (StrEqual(arPlayersA[i], sSteamID64)) {
				return (GameRules_GetProp("m_bAreTeamsFlipped", 1, 0) == 1 ? 3 : 2);
			} else if (StrEqual(arPlayersB[i], sSteamID64)) {
				return (GameRules_GetProp("m_bAreTeamsFlipped", 1, 0) == 1 ? 2 : 3);
			}
		}
	}
	return -1;
}

public void OnClientAuthorized(int client, const char[] auth) {
	if (bIsL4D2Center &&
	iServerReserved == 1 &&
	!IsFakeClient(client) &&
	GetClientLobbyParticipant(client) == -1
	) {
		KickOnSpecsExceed(client);
	}
}

public void OnClientPutInServer(int client) {
	if (bIsL4D2Center &&
	iServerReserved == 1 &&
	!IsFakeClient(client) &&
	!IsClientAuthorized(client) &&
	GetClientLobbyParticipant(client) == -1
	) {
		KickOnSpecsExceed(client);
	}
}

public void OnClientConnected(int client) {
	if (bGameEnded && !IsFakeClient(client)) {
		KickClient(client, "Game ended, you cant connect to this server now");
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if (!bWaitFirstReadyUp) {
		bInRound = false;
		bTankKilled = false;
		if (GameRules_GetProp("m_bInSecondHalfOfRound") == 1) {

			bInMapTransition = true;
			iMapsFinished++;

			iSettledScores[0] = GameRules_GetProp("m_iCampaignScore", 4, 0);
			iSettledScores[1] = GameRules_GetProp("m_iCampaignScore", 4, 1);

			if (IsLastMap()) {
				bGameFinished = true;
				CreateTimer(0.4, UpdateGameResults);
			}
		}
		int iHumanSurv;
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2) {
				iHumanSurv++;
			}
		}
		int iCurSurvivors = GameRules_GetProp("m_bAreTeamsFlipped") == 1 ? 1 : 0;
		if (iHumanSurv >= 4) {
			if (!StrEqual(sDominator[iCurSurvivors], "none")) {
				int iMvpSI = SURVMVP_GetMVP();
				int iMvpCI = SURVMVP_GetMVPCI();
				if (iMvpSI > 0 && iMvpCI > 0 && iMvpSI == iMvpCI && SURVMVP_GetMVPDmgPercent(iMvpSI) > 33.3) {
					char sSteamID64[20];
					GetClientAuthId(iMvpSI, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64), false);
					if (StrEqual(sDominator[iCurSurvivors], "")) {
						strcopy(sDominator[iCurSurvivors], 20, sSteamID64);
					} else if (!StrEqual(sDominator[iCurSurvivors], sSteamID64)) {
						strcopy(sDominator[iCurSurvivors], 20, "none");
					}
				} else {
					strcopy(sDominator[iCurSurvivors], 20, "none");
				}
			}
			if (!StrEqual(sInferior[iCurSurvivors], "none")) {
				int iLvpSI;
				float fLeastDmgPrc = 999.0;
				for (int i = 1; i <= MaxClients; i++) {
					if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == 2) {
						float fDmgPrc = SURVMVP_GetMVPDmgPercent(i);
						if (fDmgPrc < fLeastDmgPrc) {
							fLeastDmgPrc = fDmgPrc;
							iLvpSI = i;
						}
					}
				}
				if (iLvpSI > 0 && fLeastDmgPrc < 13.0) {
					char sSteamID64[20];
					GetClientAuthId(iLvpSI, AuthId_SteamID64, sSteamID64, sizeof(sSteamID64), false);
					if (StrEqual(sInferior[iCurSurvivors], "")) {
						strcopy(sInferior[iCurSurvivors], 20, sSteamID64);
					} else if (!StrEqual(sInferior[iCurSurvivors], sSteamID64)) {
						strcopy(sInferior[iCurSurvivors], 20, "none");
					}
				} else {
					strcopy(sInferior[iCurSurvivors], 20, "none");
				}
			}
		}
	}
}

public void OnTankDeath() {
	if (bInRound) {
		bTankKilled = true;
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0) {
		iLastActivity[client] = 0;
	}
}

KickOnSpecsExceed(client) {
	int iCurSpecs;
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientConnected(i) && !IsFakeClient(i) && GetClientLobbyParticipant(i) == -1) {
			iCurSpecs++;
		}
	}
	if (iCurSpecs > iMaxSpecs) {
		KickClient(client, "No more slots left for spectators");
	}
}








//AFK part
public void OnPlayerRunCmdPost(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2]) {
	if (bIsL4D2Center && client > 0 && client <= MaxClients && (iPrevButtons[client] != buttons || iPrevMouse[client][0] != mouse[0] || iPrevMouse[client][1] != mouse[1]) && IsClientInGame(client) && !IsFakeClient(client)) {
		iPrevButtons[client] = buttons;
		iPrevMouse[client][0] = mouse[0];
		iPrevMouse[client][1] = mouse[1];
		iLastActivity[client] = GetTime();
	}
}

Action OnCallVote(int client, const char[] command, int argc) {
	if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
		iLastActivity[client] = GetTime();
	}
	return Plugin_Handled;
}

Action OnCommandExecute(int client, const char[] command, int argc) {
	if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
		iLastActivity[client] = GetTime();
	}
	return Plugin_Continue;
}

public Action Ready_Cmd(int client, int args) {
	if (client > 0 && IsClientInGame(client) && !IsFakeClient(client)) {
		iLastActivity[client] = GetTime();
	}
	return Plugin_Handled;
}

public Action Timer_CountAbsence(Handle timer) {

	if (iServerReserved == 1 && !bWaitFirstReadyUp) {
		int iTime = GetTime();
		for (int i = 0; i < 8; i++) {

			int client = GetClientBySteamID64(arPlayersAll[i]);

			//Different absence calculations if game paused
			if (IsInPause()) {
				if (bResponsibleForPause[i]) {
					if (arPlayersAll[i][0] == '7') {
						iAbsenceCounter[i] = iAbsenceCounter[i] + 1;
						iSingleAbsence[i] = iSingleAbsence[i] + 1;
					}
				}
				if (client > 0 && bResponsibleForPause[i]) {
					int iTeam = GetClientTeam(client);
					if (iTeam == 0 || (iTeam > 0 && iTime - iLastActivity[client] < 30)) {
						ServerCommand("sm_forceunpause");
						SetResponsibleForPause(-1);
					}
				}
			} else {
				int player = (client > 0 && GetClientTeam(client) > 0) ? client : -1;
				if (player > 0) {
					int iTeam = GetClientTeam(player);
					if (bInRound) {
						if (iTeam > 1) {
							if (iTime - iLastActivity[player] >= 30) {
								if (arPlayersAll[i][0] == '7') {
									iAbsenceCounter[i] = iAbsenceCounter[i] + 1;
									iSingleAbsence[i] = iSingleAbsence[i] + 1;
									if (iTime - iLastUnpause >= 5) {
										if (IsGoodTimeForPause()) {
											ServerCommand("sm_forcepause");
											SetResponsibleForPause(i);
										}
										if (!bPrinted[i]) {
											bPrinted[i] = true;
											PrintToChatAll("[l4d2center.com] %N is AFK. If he doesnt ready up in %d seconds, the game ends", player, MinVal(iMaxAbsent - iAbsenceCounter[i], iMaxSingleAbsent));
										}
										return Plugin_Continue;
									}
								}
							} else {
								if (bPrinted[i]) {
									bPrinted[i] = false;
								}
								if (iSingleAbsence[i] != 0) {
									iSingleAbsence[i] = 0;
								}
							}
						} else if (iTeam == 1) {
							if (arPlayersAll[i][0] == '7') {
								iAbsenceCounter[i] = iAbsenceCounter[i] + 1;
								iSingleAbsence[i] = iSingleAbsence[i] + 1;
								if (iTime - iLastUnpause >= 5) {
									if (IsGoodTimeForPause()) {
										ServerCommand("sm_forcepause");
										SetResponsibleForPause(i);
									}
									if (!bPrinted[i]) {
										bPrinted[i] = true;
										PrintToChatAll("[l4d2center.com] %N left the game. If he doesnt come back and ready up in %d seconds, the game ends", player, MinVal(iMaxAbsent - iAbsenceCounter[i], iMaxSingleAbsent));
									}
									return Plugin_Continue;
								}
							}
						}
					} else if (IsInReady() && (iTeam <= 1 || !IsReady(player))) {
						if (arPlayersAll[i][0] == '7') {
							iAbsenceCounter[i] = iAbsenceCounter[i] + 1;
							iSingleAbsence[i] = iSingleAbsence[i] + 1;
						}
					}
				} else {
					if (arPlayersAll[i][0] == '7') {
						iAbsenceCounter[i] = iAbsenceCounter[i] + 1;
						iSingleAbsence[i] = iSingleAbsence[i] + 1;
						if (bInRound && (iTime - iLastUnpause) >= 5) {
							if (IsGoodTimeForPause()) {
								ServerCommand("sm_forcepause");
								SetResponsibleForPause(i);
							}
							if (!bPrinted[i]) {
								bPrinted[i] = true;
								PrintToChatAll("[l4d2center.com] %s left the game. If he doesnt come back in %d seconds, the game ends", arPlayersAll[i], MinVal(iMaxAbsent - iAbsenceCounter[i], iMaxSingleAbsent));
							}
							return Plugin_Continue;
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

SetResponsibleForPause(int iLobbyPlayer) {
	for (int i = 0; i < 8; i++) {
		bResponsibleForPause[i] = false;
		bPrinted[i] = false;
	}
	if (iLobbyPlayer >= 0) {
		bResponsibleForPause[iLobbyPlayer] = true;
	}
}

public OnUnpause() {
	if (bIsL4D2Center) {
		iLastUnpause = GetTime();
	}
}

bool IsGoodTimeForPause() {
	if (GameRules_GetProp("m_bInSecondHalfOfRound") == 1 && IsLastMap()) {
		return false;
	}
	return true;
}

bool IsLastMap() {
	char sCurMap[128];
	GetCurrentMap(sCurMap, sizeof(sCurMap));
	if (StrEqual(sCurMap, sLastMap, false)) {
		return true;
	}
	return false;
}

bool IsTankInPlay() {
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i) && GetClientTeam(i) == 3 && IsPlayerAlive(i) && GetEntProp(i, Prop_Send, "m_zombieClass") == 8) {
			return true;
		}
	}
	return false;
}

int MinVal(int val1, int val2) {
	if (val1 < val2) {
		return val1;
	}
	return val2;
}












//survivor_mvp include
native int SURVMVP_GetMVP();
native float SURVMVP_GetMVPDmgPercent(int client);
native int SURVMVP_GetMVPCI();
native float SURVMVP_GetMVPCIPercent(int client);

public SharedPlugin __pl_survivor_mvp =
{
	name = "survivor_mvp",
	file = "survivor_mvp.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_survivor_mvp_SetNTVOptional()
{
	MarkNativeAsOptional("SURVMVP_GetMVP");
	MarkNativeAsOptional("SURVMVP_GetMVPDmgPercent");
	MarkNativeAsOptional("SURVMVP_GetMVPCI");
	MarkNativeAsOptional("SURVMVP_GetMVPCIPercent");
}
#endif

//l4d_tank_damage_announce include
public SharedPlugin __pl_l4d_tank_damage_announce =
{
	name = "l4d_tank_damage_announce",
	file = "l4d_tank_damage_announce.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};