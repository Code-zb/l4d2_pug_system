package api

import (
	"github.com/gin-gonic/gin"
	"time"
    "strconv"
	"../settings"
	"../players"
	"../players/auth"
)


func HttpReqStatus(c *gin.Context) {

	mapResponse := make(map[string]interface{});

	i64CurTime := time.Now().UnixMilli();

	sCookieSessID, errCookieSessID := c.Cookie("session_id");
	sCookiePlayersUpdatedAt, _ := c.Cookie("players_updated_at");
	i64CookiePlayersUpdatedAt, _ := strconv.ParseInt(sCookiePlayersUpdatedAt, 10, 64);
	sCookiePlayerUpdatedAt, _ := c.Cookie("player_updated_at");
	i64CookiePlayerUpdatedAt, _ := strconv.ParseInt(sCookiePlayerUpdatedAt, 10, 64);

	mapResponse["success"] = true;
	mapResponse["no_new_lobbies"] = settings.NoNewLobbies;
	mapResponse["brokenmode"] = settings.BrokenMode;
	mapResponse["time"] = i64CurTime;
	if (i64CookiePlayersUpdatedAt <= players.I64LastPlayerlistUpdate) {
		mapResponse["need_update_players"] = true;
	} else {
		mapResponse["need_update_players"] = false;
	}

	mapResponse["authorized"] = false;
	if (errCookieSessID == nil && sCookieSessID != "") {
		oSession, bAuthorized := auth.GetSession(sCookieSessID);
		if (bAuthorized) {
			mapResponse["authorized"] = true;
			players.MuPlayers.Lock();
			players.UpdatePlayerActivity(oSession.SteamID64);
			if (i64CookiePlayerUpdatedAt <= players.MapPlayers[oSession.SteamID64].LastChanged) {
				mapResponse["need_update_player"] = true;
			} else {
				mapResponse["need_update_player"] = false;
			}
			players.MuPlayers.Unlock();
		}
	}

	c.Header("Access-Control-Allow-Origin", "*");
	c.JSON(200, mapResponse);
}