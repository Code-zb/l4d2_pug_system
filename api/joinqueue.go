package api

import (
	"github.com/gin-gonic/gin"
	"../players/auth"
	"../players"
	"../queue"
	"../smurf"
	"../bans"
	"fmt"
	"time"
	"encoding/base64"
)


func HttpReqJoinQueue(c *gin.Context) {

	mapResponse := make(map[string]interface{});

	sCookieSessID, errCookieSessID := c.Cookie("session_id");

	mapResponse["success"] = false;
	if (errCookieSessID == nil && sCookieSessID != "") {
		oSession, bAuthorized := auth.GetSession(sCookieSessID);
		if (bAuthorized) {

			players.MuPlayers.Lock();

			i64CurTime := time.Now().UnixMilli();
			pPlayer := players.MapPlayers[oSession.SteamID64];
			if (pPlayer.IsInQueue) {
				mapResponse["error"] = "You are already in queue";
			} else if (pPlayer.IsInGame) {
				mapResponse["error"] = "You cant join queue, finish your game first";
			} else if (queue.NewGamesBlocked) {
				mapResponse["error"] = "The site is going to be restarted soon, new games are not allowed";
			} else if (pPlayer.NextQueueingAllowed > i64CurTime) {
				mapResponse["error"] = fmt.Sprintf("You are temporarily blocked from joining games. Please wait %d seconds.", (pPlayer.NextQueueingAllowed - i64CurTime) / 1000);
			} else if (!pPlayer.IsOnline) {
				mapResponse["error"] = "Somehow you are not Online, try to refresh the page";
			} else if (!pPlayer.ProfValidated) {
				mapResponse["error"] = "Please validate your profile first";
			} else if (!pPlayer.RulesAccepted) {
				mapResponse["error"] = "Please accept our rules first";
			} else if (pPlayer.Access <= -2) {
				mapResponse["error"] = "Sorry, you are banned, you gotta wait until it expires";
			} else {

				queue.Join(pPlayer)
				mapResponse["success"] = true;

				sCookieUniqueKey, _ := c.Cookie("auth2");
				byNickname, _ := base64.StdEncoding.DecodeString(pPlayer.NicknameBase64);
				go smurf.AnnounceIPAndKey(pPlayer.SteamID64, c.ClientIP(), string(byNickname), sCookieUniqueKey);
				go func(sSteamID64 string)() {bans.ChanAutoBanSmurfs <- smurf.GetKnownAccounts(sSteamID64);}(oSession.SteamID64);
			}
			players.MuPlayers.Unlock();

		} else {
			mapResponse["error"] = "Please authorize first";
		}
	} else {
		mapResponse["error"] = "Please authorize first";
	}

	c.Header("Access-Control-Allow-Origin", c.Request.Header.Get("origin"));
	c.Header("Access-Control-Allow-Credentials", "true");
	c.JSON(200, mapResponse);
}