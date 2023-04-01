#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <nativevotes>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN


public Plugin myinfo =
{
	name = "Weapon vote",
	author = "TouchMe",
	description = "Issues weapons based on voting results",
	version = "1.1.1"
};


#define LIB_READY              "readyup"

#define TRANSLATIONS            "weapon_vote.phrases"
#define CONFIG_FILEPATH         "configs/weapon_vote.ini"

#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define VOTE_TEAM               TEAM_INFECTED
#define VOTE_TIME               15

#define MENU_TITLE_SIZE         64
#define VOTE_TITLE_SIZE         128
#define VOTE_MSG_SIZE           128

#define WEAPON_NAME_SIZE        32
#define WEAPON_TITLE_SIZE       64
#define WEAPON_CMD_SIZE         32


#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define IS_VALID_SURVIVOR(%1)   (IS_VALID_INGAME(%1) && IS_SURVIVOR(%1))
#define IS_SURVIVOR_ALIVE(%1)   (IS_VALID_SURVIVOR(%1) && IsPlayerAlive(%1))


enum struct WeaponVoteList
{
	ArrayList name;
	ArrayList title;
	StringMap cmd;
	int size;

	void Create()
	{
		this.title = new ArrayList(ByteCountToCells(WEAPON_TITLE_SIZE));
		this.name = new ArrayList(ByteCountToCells(WEAPON_NAME_SIZE));
		this.cmd = new StringMap();
	}
	
	void Close()
	{
		delete this.title;
		delete this.name;
		delete this.cmd;
	}

	void AddItem(char[] sName, char[] sTitle, char[] sCmd)
	{
		this.title.PushString(sTitle);
		this.name.PushString(sName);
		this.cmd.SetValue(sCmd, this.size ++);
	}

	int Size() {
		return this.size; 
	}
}

int
	g_iVotingItem = 0;

bool
	g_bReadyUpAvailable = false,
	g_bRoundIsLive = false;

WeaponVoteList
	g_hWeaponVoteList;


/**
  * Global event. Called when all plugins loaded.
  *
  * @noreturn
  */
public void OnAllPluginsLoaded() {
	g_bReadyUpAvailable = LibraryExists(LIB_READY);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName 			Library name.
  *
  * @noreturn
  */
public void OnLibraryRemoved(const char[] sName) 
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = false;
	}
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName 			Library name.
  *
  * @noreturn
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, LIB_READY)) {
		g_bReadyUpAvailable = true;
	}
}

/**
  * Called before OnPluginStart.
  *
  * @noreturn
  */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
  * Loads dictionary files. On failure, stops the plugin execution.
  *
  * @noreturn
  */
void InitTranslations() 
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/" ... TRANSLATIONS ... ".txt");

	if (FileExists(sPath)) {
		LoadTranslations(TRANSLATIONS);
	} else {
		SetFailState("Path %s not found", sPath);
	}
}

/**
  * Called when the map starts loading.
  *
  * @noreturn
  */
public void OnMapInit(const char[] sMapName) {
	g_bRoundIsLive = false;
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 * 
 * @noreturn
 */
public void OnPluginStart()
{
	InitTranslations();
	
	g_hWeaponVoteList.Create();

	ReadWeaponVoteList();
	
	HookEvent("versus_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

/**
 * Called when the plugin is about to be unloaded.
 * 
 * @noreturn
 */
public void OnPluginEnd()
{
	g_hWeaponVoteList.Close();
}

/**
  * File reader. Opens and reads lines in config/weapon_vote.ini.
  *
  * @noreturn
  */
void ReadWeaponVoteList()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, CONFIG_FILEPATH);
	
	if (!FileExists(sPath)) {
		SetFailState("Path %s not found", sPath);
	}

	File hFile = OpenFile(sPath, "rt");
	if (!hFile) {
		SetFailState("Could not open file!");
	}
	
	while (!hFile.EndOfFile())
	{
		char sCurLine[255];
		if (!hFile.ReadLine(sCurLine, sizeof(sCurLine))) {
			break;
		}
		
		int iLineLength = strlen(sCurLine);

		for (int iChar = 0; iChar < iLineLength; iChar++)
		{
			if (sCurLine[iChar] == '/' && iChar != iLineLength - 1 && sCurLine[iChar+1] == '/')
			{
				sCurLine[iChar] = '\0';
				break;
			}
		}
		
		TrimString(sCurLine);
		
		if ((sCurLine[0] == '/' && sCurLine[1] == '/') || (sCurLine[0] == '\0')) {
			continue;
		}
	
		ParseLine(sCurLine);
	}
	
	hFile.Close();
}

/**
  * File line parser.
  *
  * @param sLine 			Line. Pattern:
  *                                        "weapon_*" "*" "sm_*"
  *
  * @noreturn
  */
void ParseLine(const char[] sLine)
{
	int iPos, iNextPos;

	// Get weapon_* id
	char sId[WEAPON_NAME_SIZE];
	iNextPos = BreakString(sLine, sId, sizeof(sId));
	iPos = iNextPos;

	// Get Weapon name (Menu item name)
	if (iNextPos == -1) {
		// Weapon name not found
		return;
	}

	char sName[WEAPON_TITLE_SIZE];
	iNextPos = BreakString(sLine[iPos], sName, sizeof(sName));
	iPos += iNextPos;


	// Get weapon cmd
	if (iNextPos == -1) {
		// Cmd not found
		return;
	}

	char sCmd[WEAPON_CMD_SIZE];
	BreakString(sLine[iPos], sCmd, sizeof(sCmd));

	g_hWeaponVoteList.AddItem(sId, sName, sCmd);
}

/**
 * Round start event.
 */
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = true;
	}

	return Plugin_Continue;
}

/**
 * Round end event.
 */
public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = false;
	}

	return Plugin_Continue;
}

/**
  * Global listener for the chat commands.
  *
  * @param iClient			Client index.
  * @param sArgs			Chat argument string.
  *
  * @return Plugin_Handled | Plugin_Continue
  */
public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
	if (!IS_VALID_CLIENT(iClient) || IsFakeClient(iClient)) {
		return Plugin_Handled;
	}
		
	char sClearCmd[WEAPON_CMD_SIZE];
	strcopy(sClearCmd, sizeof(sClearCmd), sArgs[1]);

	if ((sArgs[0] == '/' || sArgs[0] == '!'))
	{
		int iItem;

		if (g_hWeaponVoteList.cmd.GetValue(sClearCmd, iItem) 
		&& CanClientStartVote(iClient)) {
			StartVote(iClient, iItem);
		}
    }

	return Plugin_Continue;
}

/**
  * Called when a client is sending a command.
  *
  * @param iClient			Client index.
  * @param iArgs			Number of arguments.
  *
  * @return Plugin_Handled | Plugin_Continue
  */
public Action OnClientCommand(int iClient, int sArgs)
{
	if (!IS_VALID_CLIENT(iClient) || IsFakeClient(iClient)) {
		return Plugin_Handled;
	}

	char sArgCmd[WEAPON_CMD_SIZE];
  	GetCmdArg(0, sArgCmd, sizeof(sArgCmd));
	strcopy(sArgCmd, sizeof(sArgCmd), sArgCmd[3]);

	int iItem;

	if (g_hWeaponVoteList.cmd.GetValue(sArgCmd, iItem) 
	&& CanClientStartVote(iClient)) {
		StartVote(iClient, iItem);
    }

	return Plugin_Continue;
}

/**
  * Start voting.
  *
  * @param iClient		Client index.
  * @param iItem		Weapon index.
  *
  * @return				Status code.
  */
public void StartVote(int iClient, int iItem) 
{
	if (!NativeVotes_IsVoteTypeSupported(NativeVotesType_Custom_YesNo))
	{
		CPrintToChat(iClient, "%T", "UNSUPPORTED", iClient);
		return;
	}

	if (!NativeVotes_IsNewVoteAllowed())
	{
		CPrintToChat(iClient, "%T", "COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	if (g_bReadyUpAvailable) {
		ToggleReadyPanel(false);
	}

	int iTotal;
	int[] iPlayers = new int[MaxClients];
	
	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || (GetClientTeam(iPlayer) != VOTE_TEAM)) {
			continue;
		}
			
		iPlayers[iTotal++] = iPlayer;
	}

	// Set Item
	g_iVotingItem = iItem;

	// Create vote
	NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo, NATIVEVOTES_ACTIONS_DEFAULT|MenuAction_Display);
	
	hVote.Initiator = iClient;
	hVote.Team = VOTE_TEAM;
	hVote.DisplayVote(iPlayers, iTotal, VOTE_TIME);

	char sWeaponName[WEAPON_TITLE_SIZE];
	g_hWeaponVoteList.title.GetString(iItem, sWeaponName, sizeof(sWeaponName));
	CPrintToChatAll("%t", "VOTE_START", iClient, sWeaponName);
}

/**
  * Callback when voting is over and results are available.
  *
  * @param hVote 			Voting ID.
  * @param iAction 			---.
  * @param iParam1 		    Client index | Vote status.
  *
  * @noreturn
  */
public int HandlerVote(NativeVote hVote, MenuAction iAction, int iParam1, int iParam2)
{
	switch (iAction)
	{
		case MenuAction_End:
		{
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(true);
			}

			hVote.Close();
		}
		
		case MenuAction_Display:
		{
			char sWeaponName[WEAPON_TITLE_SIZE];
			g_hWeaponVoteList.title.GetString(g_iVotingItem, sWeaponName, sizeof(sWeaponName));

			char sVoteTitle[VOTE_TITLE_SIZE];
			Format(sVoteTitle, sizeof(sVoteTitle), "%T", "VOTE_TITLE", iParam1, hVote.Initiator, sWeaponName);

			NativeVotes_RedrawVoteTitle(sVoteTitle);

			return view_as<int>(Plugin_Changed);
		}
		
		case MenuAction_VoteCancel:
		{
			if (iParam1 == VoteCancel_NoVotes) {
				hVote.DisplayFail(NativeVotesFail_NotEnoughVotes);
			}
			
			else {
				hVote.DisplayFail(NativeVotesFail_Generic);
			}
		}
		
		case MenuAction_VoteEnd:
		{
			if (iParam1 == NATIVEVOTES_VOTE_NO 
				|| (!g_bReadyUpAvailable && g_bRoundIsLive)
				|| (g_bReadyUpAvailable && !IsInReady())
				|| !IsClientInGame(hVote.Initiator)) {
				hVote.DisplayFail(NativeVotesFail_Loses);
			}

			else
			{
				char sWeaponTitle[WEAPON_TITLE_SIZE];
 				g_hWeaponVoteList.title.GetString(g_iVotingItem, sWeaponTitle, sizeof(sWeaponTitle));

				char sVoteMsg[VOTE_MSG_SIZE];

				for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
				{
					if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || (GetClientTeam(iPlayer) != VOTE_TEAM)) {
						continue;
					}

					SetGlobalTransTarget(iPlayer);
					Format(sVoteMsg, sizeof(sVoteMsg), "%T", "VOTE_PASS", iPlayer, hVote.Initiator, sWeaponTitle);
					hVote.DisplayPassCustomToOne(iPlayer, sVoteMsg);
				}

				if (IS_SURVIVOR_ALIVE(hVote.Initiator))
				{
					char sWeaponName[WEAPON_NAME_SIZE];
					g_hWeaponVoteList.name.GetString(g_iVotingItem, sWeaponName, sizeof(sWeaponName));
					GivePlayerItem(hVote.Initiator, sWeaponName);
				}
			}
		}
	}
	
	return 0;
}

/**
  * @param iClient          Client ID
  *
  * @return                 true if succes
  */
bool CanClientStartVote(int iClient)
{
	if (!IS_VALID_SURVIVOR(iClient))
	{
		CPrintToChat(iClient, "%T", "ONLY_SURVIVOR", iClient);
		return false;
	}

	if (g_bReadyUpAvailable && !IsInReady())
	{
		CPrintToChat(iClient, "%T", "LEFT_READYUP", iClient);
		return false;
	} 
	
	if (!g_bReadyUpAvailable && g_bRoundIsLive)
	{
		CPrintToChat(iClient, "%T", "ROUND_LIVE", iClient);
		return false;
	}

	return true;
}
