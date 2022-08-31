package main

import (
	"fmt"
	"./settings"
	"./players"
	"./database"
	"./lobby"
	"./api"
	"./games"
	"./players/auth"
	"time"
	//"./utils"
	//"crypto/rand"
	//"math/big"
	//"encoding/json"
	//"encoding/base64"
)


func main() {
	fmt.Printf("Started.\n");

	//Parse settings
	if (!settings.Parse()) {
		return;
	}

	//Permanent global database connection
	if (!database.DatabaseConnect()) {
		return;
	}

	//Restore from database
	if (!players.RestorePlayers()) {
		return;
	}
	if (!auth.RestoreSessions()) {
		return;
	}
	lobby.I64LastLobbyListUpdate = time.Now().UnixMilli();

	//HTTP server init
	api.GinInit();

	go players.WatchOnline(); //send players to offline mode
	go api.AuthRatelimits(); //limit authorization requests per ip
	go lobby.WatchLobbies(); //watch lobbies for ready and timeout
	go games.ChannelWatchers(); //watch various game related channels




	//Test
	//go TestingFromMain();


	//Block until shutdown command is received
	fmt.Printf("End: %v\n", <-api.ChShutdown);
}

/*func TestingFromMain() {
	time.Sleep(10 * time.Second);


	for i := 1; i <= 8; i++ {
		sGenSteamID64, _ := utils.GenerateRandomString(17, "12345689");
		sGenName, _ := utils.GenerateRandomString(10, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz");
		pPlayer := &players.EntPlayer{
			SteamID64:			sGenSteamID64,
			NicknameBase64:		base64.StdEncoding.EncodeToString([]byte(sGenName)),
			Mmr:				int((time.Now().UnixNano() % 3000) + 1),
			MmrUncertainty:		settings.DefaultMmrUncertainty,
			ProfValidated:		true,
			RulesAccepted:		true,
			LastActivity:		time.Now().UnixMilli(),
			IsOnline:			true,
			OnlineSince:		time.Now().UnixMilli(),
			LastLobbyActivity:	time.Now().UnixMilli(), //Last lobby activity //unix timestamp in milliseconds
		};
		players.MapPlayers[sGenSteamID64] = pPlayer;
		players.ArrayPlayers = append(players.ArrayPlayers, pPlayer);
	}
	players.I64LastPlayerlistUpdate = time.Now().UnixMilli();


	for _, pPlayer := range players.ArrayPlayers {
		if (pPlayer.IsOnline && !pPlayer.IsInLobby && !pPlayer.IsInGame) {
			lobby.JoinAny(pPlayer);
		}
	}

	time.Sleep(5 * time.Second);

	for _, pPlayer := range players.ArrayPlayers {
		if (pPlayer.IsInLobby && !pPlayer.IsReadyInLobby) {
			time.Sleep(1 * time.Second);
			lobby.Ready(pPlayer);
		}
	}

}*/