package api

import (
	"fmt"
	"github.com/gin-gonic/gin"
	"../players/auth"
	"../games"
	"../players"
)


func HttpReqGSGetGame(c *gin.Context) {

	var sResponse string = "\"VDFresponse\"\n{";


	sAuthKey := c.PostForm("auth_key");
	if (auth.Backend(sAuthKey)) {
		sIP := c.PostForm("ip");
		if (sIP != "") {
			games.MuGames.Lock();
			pGame := games.GetGameByIP(sIP);
			if (pGame != nil) {

				sResponse = fmt.Sprintf("%s\n	\"success\" \"1\"", sResponse);

				players.MuPlayers.Lock();
				for i := 0; i < 4; i++ {
					sResponse = fmt.Sprintf("%s\n	\"player_a%d\" \"%s\"", sResponse, i, pGame.PlayersA[i].SteamID64);
				}
				for i := 0; i < 4; i++ {
					sResponse = fmt.Sprintf("%s\n	\"player_b%d\" \"%s\"", sResponse, i, pGame.PlayersB[i].SteamID64);
				}
				players.MuPlayers.Unlock();

				sResponse = fmt.Sprintf("%s\n	\"confogl\" \"%s\"", sResponse, pGame.GameConfig.CodeName);
				sResponse = fmt.Sprintf("%s\n	\"first_map\" \"%s\"", sResponse, pGame.Maps[0]);
				sResponse = fmt.Sprintf("%s\n	\"last_map\" \"%s\"", sResponse, pGame.Maps[len(pGame.Maps) - 1]);
				sResponse = fmt.Sprintf("%s\n	\"mmr_min\" \"%d\"", sResponse, pGame.MmrMin);
				sResponse = fmt.Sprintf("%s\n	\"mmr_max\" \"%d\"", sResponse, pGame.MmrMax);

				if (pGame.State == games.StateWaitPlayersJoin) {
					sResponse = fmt.Sprintf("%s\n	\"game_state\" \"wait_readyup\"", sResponse);
				} else {
					sResponse = fmt.Sprintf("%s\n	\"game_state\" \"other\"", sResponse);
				}

			} else {
				sResponse = fmt.Sprintf("%s\n	\"success\" \"0\"", sResponse);
				sResponse = fmt.Sprintf("%s\n	\"error\" \"No game on this IP\"", sResponse);
			}
			games.MuGames.Unlock();
		} else {
			sResponse = fmt.Sprintf("%s\n	\"success\" \"0\"", sResponse);
			sResponse = fmt.Sprintf("%s\n	\"error\" \"No ip parameter\"", sResponse);
		}

	} else {
		sResponse = fmt.Sprintf("%s\n	\"success\" \"0\"", sResponse);
		sResponse = fmt.Sprintf("%s\n	\"error\" \"Bad auth key\"", sResponse);
	}


	sResponse = sResponse + "\n}\n";
	c.String(200, sResponse);
}