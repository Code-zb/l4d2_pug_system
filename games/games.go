package games

import (
	"fmt"
	"sync"
	"time"
	"strings"
	"../players"
	"../settings"
	"../rating"
	"../utils"
)

type EntGame struct {
	ID					string
	CreatedAt			int64 //milliseconds
	PlayersUnpaired		[]*players.EntPlayer
	PlayersA			[]*players.EntPlayer
	PlayersB			[]*players.EntPlayer
	GameConfig			settings.ConfoglConfig
	CampaignName		string
	Maps				[]string
	State				int
	ServerIP			string
	GameResult			rating.EntGameResult
	ReceiverFullRUP		chan bool
	ReceiverReadyList	chan []string
	ReceiverResult		chan rating.EntGameResult
}

const ( //game states
	StateDummy int = iota
	StateCreating
	StateCreated
	StateCampaignChosen
	StateTeamsPicked
	StateWaitPings
	StateSelectServer
	StateNoServers
	StateWaitPlayersJoin
	StateReadyUpExpired
	StateGameProceeds
	StateGameEnded
)

var MapGameStatus map[int]string;

var IPlayersFinishingGameSoon int;

var MapGames map[string]*EntGame = make(map[string]*EntGame);
var ArrayGames []*EntGame; //duplicate of MapGames, for faster iterating
var MuGames sync.RWMutex;

var ChanNewGameID chan string = make(chan string);


func Watchers() {
	go HandleUniqID();
	go CheckVersion();
	go WatchFinishingGameSoon();

	//init game statuses text for response
	MapGameStatus = map[int]string{
		StateCreating:			"Creating game",
		StateCreated:			"Game created",
		StateCampaignChosen:	"Campaign selected",
		StateTeamsPicked:		"Players paired",
		StateWaitPings:			"Pinging servers",
		StateSelectServer:		"Selecting best available server",
		StateNoServers:			"No free servers available. If no server found in 5 minutes, the game ends.",
		StateWaitPlayersJoin:	"The server is ready. You have "+fmt.Sprintf("%d", settings.FirstReadyUpExpire / 60)+" minutes to join the server and Ready Up.",
		StateReadyUpExpired:	"Some players failed to Ready Up in time",
		StateGameProceeds:		"In game",
		StateGameEnded:			"Game ended",
	}
}

func HandleUniqID() {
	for {
		select {
			case ChanNewGameID <- func()(string) {
				sRand, _ := utils.GenerateRandomString(3, "abcdefghkmnpqrstuvwxyz");
				return fmt.Sprintf("%d%s", time.Now().UnixNano(), sRand);
			}():
		}
		time.Sleep(1 * time.Nanosecond);
	}
}

func WatchFinishingGameSoon() {
	for {
		players.MuPlayers.Lock();
		MuGames.RLock();
		iCounter := 0;
		i64CurTime := time.Now().UnixMilli();

		for _, pPlayer := range players.ArrayPlayers {
			if (pPlayer.IsInGame) {
				oGameResult := MapGames[pPlayer.GameID].GameResult;
				if (oGameResult.IsLastMap && oGameResult.CurrentHalf == 2) {
					iCounter++;
				}
			} else {
				if (pPlayer.LastGameActivity + 60000/*60s*/ > i64CurTime) {
					iCounter++;
				}
			}
		}

		if (IPlayersFinishingGameSoon != iCounter) {
			IPlayersFinishingGameSoon = iCounter;
			for _, pPlayer := range players.ArrayPlayers {
				if (pPlayer.IsInQueue) {
					pPlayer.LastQueueChanged = i64CurTime;
				}
			}
			players.I64LastPlayerlistUpdate = i64CurTime;
		}

		MuGames.RUnlock();
		players.MuPlayers.Unlock();
		time.Sleep(10 * time.Second);
	}
}


func Create(pGame *EntGame) { //MuGames and MuPlayers must be locked outside
	MapGames[pGame.ID] = pGame;
	ArrayGames = append(ArrayGames, pGame);
	i64CurTime := time.Now().UnixMilli();
	var iMmrSum int;
	for _, pPlayer := range pGame.PlayersUnpaired {
		pPlayer.IsInGame = true;
		pPlayer.GameID = pGame.ID;
		pPlayer.LastGameActivity = i64CurTime;
		iMmrSum = iMmrSum + pPlayer.Mmr;
	}
	pGame.GameConfig = ChooseConfoglConfig(iMmrSum / 8);
	players.I64LastPlayerlistUpdate = i64CurTime;
}

func Destroy(pGame *EntGame) { //MuGames and MuPlayers must be locked outside
	delete(MapGames, pGame.ID);
	iMaxG := len(ArrayGames);
	for i := 0; i < iMaxG; i++ {
		if (ArrayGames[i].ID == pGame.ID) {
			ArrayGames[i] = ArrayGames[iMaxG - 1];
			ArrayGames = ArrayGames[:(iMaxG - 1)];
			break;
		}
	}
	i64CurTime := time.Now().UnixMilli();
	for _, pPlayer := range pGame.PlayersUnpaired {
		pPlayer.IsInGame = false;
		pPlayer.GameID = "";
		pPlayer.LastGameChanged = i64CurTime;
		pPlayer.LastGameActivity = i64CurTime;
	}
	players.I64LastPlayerlistUpdate = i64CurTime;
}

func SetLastUpdated(arPlayers []*players.EntPlayer) { //Players must be locked outside
	i64CurTime := time.Now().UnixMilli();
	for _, pPlayer := range arPlayers {
		pPlayer.LastGameChanged = i64CurTime;
	}
}

func GetGameByIP(sIP string) (*EntGame) { //Games must be locked outside
	if (sIP == "") {
		return nil;
	}
	for _, pGame := range ArrayGames {
		if (pGame.ServerIP == sIP) {
			return pGame;
		}
	}
	return nil;
}

func ChooseConfoglConfig(iMmr int) (settings.ConfoglConfig) {
	if (settings.BrokenMode) {
		return settings.ConfoglConfig{
			CodeName:		"default",
			Name:			"Default",
			MmrMax:			2000000000,
		};
	}
	iLen := len(settings.ArrayConfoglConfigsMmrs);
	if (iLen == 1) {
		return settings.MapConfoglConfigs[settings.ArrayConfoglConfigsMmrs[0]];
	}
	for i := 0; i < iLen; i++ {
		if (iMmr < settings.ArrayConfoglConfigsMmrs[i]) {
			return settings.MapConfoglConfigs[settings.ArrayConfoglConfigsMmrs[i]];
		}
	}
	return settings.ConfoglConfig{
		CodeName:		"zonemod",
		Name:			"nani?",
		MmrMax:			2000000000,
	}; //shouldn't happen
}

func ChooseCampaign(arPlayers []*players.EntPlayer) int {
	var arCampaigns []int;
	for i, _ := range settings.CampaignNames {
		arCampaigns = append(arCampaigns, i);
	}

	for _, pPlayer := range arPlayers {
		if (pPlayer.LastCampaignPlayed > 0) {
			iIndex := utils.GetIntIdxInArray(pPlayer.LastCampaignPlayed - 1, arCampaigns);
			if (iIndex != -1) {
				arCampaigns = utils.RemoveIntFromArray(iIndex, arCampaigns);
			}
		}
	}

	if (len(arCampaigns) > 0) {
		iBuffer, _ := utils.GetRandInt(0, len(arCampaigns) - 1);
		return arCampaigns[iBuffer];
	} else {
		iBuffer, _ := utils.GetRandInt(0, len(settings.CampaignNames) - 1);
		return iBuffer;
	}
}

func Implode4Players(arPlayers []*players.EntPlayer) string {
	var sSteamID64s string = arPlayers[0].SteamID64;
	for i := 1; i < 4; i++ {
		sSteamID64s = sSteamID64s + "," + arPlayers[i].SteamID64;
	}
	return sSteamID64s;
}

func FormatPingsLog(arPlayers []*players.EntPlayer) string {
	var arFormatPings []string;
	for _, pPlayer := range arPlayers {
		for sIP, iPing := range pPlayer.GameServerPings {
			arFormatPings = append(arFormatPings, fmt.Sprintf("%s->%s: %d", pPlayer.SteamID64, sIP, iPing));
		}
	}
	if (len(arFormatPings) > 0) {
		return strings.Join(arFormatPings, ", ");
	}
	return "none";
}