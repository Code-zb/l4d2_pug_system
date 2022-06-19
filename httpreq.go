package main

import (
	"github.com/gin-gonic/gin"
	"./settings"
	"./auth"
	"io/ioutil"
	"fmt"
	"time"
	"./players"
)


func ginInit() {
	gin.SetMode(gin.ReleaseMode); //disable debug logs
	gin.DefaultWriter = ioutil.Discard; //disable output
	r := gin.Default();
	r.MaxMultipartMemory = 1 << 20;

	r.POST("/status", HttpReqStatus);
	r.POST("/shutdown", HttpReqShutdown);
	r.POST("/addauth", HttpReqAddAuth);
	r.POST("/removeauth", HttpReqRemoveAuth);
	r.POST("/updateactivity", HttpReqUpdateActivity);
	r.POST("/getplayer", HttpReqGetPlayer);
	
	fmt.Printf("Starting web server\n");
	go r.Run(":"+settings.ListenPort); //Listen on port
}



func HttpReqStatus(c *gin.Context) {

	mapResponse := make(map[string]interface{});
	if (!auth.Backend(c.PostForm("backend_auth"))) {
		mapResponse["success"] = false;
		mapResponse["error"] = 1;
		c.JSON(200, mapResponse);
		return;
	}

	mapResponse["success"] = true;
	mapResponse["shutdown"] = bStateShutdown;
	mapResponse["time"] = time.Now().UnixMilli();
	mapResponse["players_updated"] = players.I64LastPlayerlistUpdate;

	sSteamID64 := c.PostForm("steamid64");
	if (sSteamID64 != "") {
		bSuccess, oPlayer, _ := players.GetPlayerResponse(sSteamID64);
		if (bSuccess) {
			mapResponse["player_updated"] = oPlayer.LastUpdated;
		}
	}
	c.JSON(200, mapResponse);
}

func HttpReqShutdown(c *gin.Context) {

	mapResponse := make(map[string]interface{});

	if (!auth.Backend(c.PostForm("backend_auth"))) {
		mapResponse["success"] = false;
		mapResponse["error"] = 1;
		c.JSON(200, mapResponse);
		return;
	}

	bSetShutdown, iError := SetShutDown();
	if (!bSetShutdown) {
		mapResponse["success"] = false;
		mapResponse["error"] = iError;
	} else {
		mapResponse["success"] = true;
	}

	c.JSON(200, mapResponse);
	go PerformShutDown();
}

func HttpReqAddAuth(c *gin.Context) {

	mapResponse := make(map[string]interface{});
	
	if (!auth.Backend(c.PostForm("backend_auth"))) {
		mapResponse["success"] = false;
		mapResponse["error"] = 1;
		c.JSON(200, mapResponse);
		return;
	}


	sSteamID64 := c.PostForm("steamid64");
	sNicknameBase64 := c.PostForm("nickname_base64");
	if (sSteamID64 == "" || sNicknameBase64 == "") {
		mapResponse["success"] = false;
		mapResponse["error"] = 2;
		c.JSON(200, mapResponse);
		return;
	}

	sSessionID := auth.AddPlayerAuth(sSteamID64, sNicknameBase64);
	mapResponse["success"] = true;
	mapResponse["session_id"] = sSessionID;
	
	c.JSON(200, mapResponse);
}

func HttpReqRemoveAuth(c *gin.Context) {

	mapResponse := make(map[string]interface{});
	
	if (!auth.Backend(c.PostForm("backend_auth"))) {
		mapResponse["success"] = false;
		mapResponse["error"] = 1;
		c.JSON(200, mapResponse);
		return;
	}


	sSessID := c.PostForm("session_id");
	if (sSessID == "") {
		mapResponse["success"] = false;
		mapResponse["error"] = 2;
		c.JSON(200, mapResponse);
		return;
	}

	bSuccess, iError := auth.RemovePlayerAuth(sSessID);
	mapResponse["success"] = bSuccess;
	if (!bSuccess) {
		mapResponse["error"] = iError;
	}
	
	c.JSON(200, mapResponse);
}

func HttpReqUpdateActivity(c *gin.Context) {

	mapResponse := make(map[string]interface{});
	
	if (!auth.Backend(c.PostForm("backend_auth"))) {
		mapResponse["success"] = false;
		mapResponse["error"] = 1;
		c.JSON(200, mapResponse);
		return;
	}


	sSteamID64 := c.PostForm("steamid64");
	if (sSteamID64 == "") {
		mapResponse["success"] = false;
		mapResponse["error"] = 2;
		c.JSON(200, mapResponse);
		return;
	}

	bSuccess, iError := players.UpdatePlayerActivity(sSteamID64);
	mapResponse["success"] = bSuccess;
	if (!bSuccess) {
		mapResponse["error"] = iError;
	}
	
	c.JSON(200, mapResponse);
}

func HttpReqGetPlayer(c *gin.Context) {

	mapResponse := make(map[string]interface{});
	
	if (!auth.Backend(c.PostForm("backend_auth"))) {
		mapResponse["success"] = false;
		mapResponse["error"] = 1;
		c.JSON(200, mapResponse);
		return;
	}


	sSteamID64 := c.PostForm("steamid64");
	if (sSteamID64 == "") {
		mapResponse["success"] = false;
		mapResponse["error"] = 2;
		c.JSON(200, mapResponse);
		return;
	}

	bSuccess, oPlayer, iError := players.GetPlayerResponse(sSteamID64);
	if (!bSuccess) {
		mapResponse["success"] = false;
		mapResponse["error"] = iError;
	} else {
		mapResponse["success"] = true;
		mapResponse["player"] = oPlayer;
	}
	
	c.JSON(200, mapResponse);
}
