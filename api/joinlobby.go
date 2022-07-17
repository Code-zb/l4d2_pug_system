package api

import (
	"github.com/gin-gonic/gin"
	"../players/auth"
	"../players"
	"../lobby"
)


func HttpReqJoinLobby(c *gin.Context) {

	mapResponse := make(map[string]interface{});
	
	sCookieSessID, errCookieSessID := c.Cookie("session_id");
	sLobbyID := c.Query("lobby_id");

	mapResponse["success"] = false;
	if (errCookieSessID == nil && sCookieSessID != "") {
		oSession, bAuthorized := auth.GetSession(sCookieSessID);
		if (bAuthorized) {
			players.MuPlayers.Lock();
			pPlayer := players.MapPlayers[oSession.SteamID64];
			if (pPlayer.IsInLobby) {
				mapResponse["error"] = 2; //already in lobby
			} else if (!pPlayer.IsOnline) {
				mapResponse["error"] = 3; //not online, wtf bro?
			} else if (pPlayer.Access == -2) {
				mapResponse["error"] = 4; //banned
			} else if (sLobbyID == "") {
				mapResponse["error"] = 5; //lobby id not set
			} else {
				//Join lobby
				if (lobby.Join(pPlayer, sLobbyID)) {
					mapResponse["success"] = true;
				} else {
					mapResponse["error"] = 6; //lobby doesn't exist or lobby full
				}
			}
			players.MuPlayers.Unlock();
		} else {
			mapResponse["error"] = 1; //unauthorized
		}
	} else {
		mapResponse["error"] = 1; //unauthorized
	}
	
	c.Header("Access-Control-Allow-Origin", "*");
	c.JSON(200, mapResponse);
}
