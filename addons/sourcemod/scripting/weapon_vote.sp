#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <nativevotes_rework>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>
#define REQUIRE_PLUGIN


public Plugin myinfo =
{
	name = "Weapon vote",
	author = "TouchMe",
	description = "Issues weapons based on voting results",
	version = "build_0001"
};


#define LIB_READY              "readyup"

#define TRANSLATIONS            "weapon_vote.phrases"
#define CONFIG_FILEPATH         "configs/weapon_vote.ini"

#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define VOTE_TEAM               TEAM_INFECTED
#define VOTE_TIME               15

#define WEAPON_NAME_SIZE        32
#define WEAPON_TITLE_SIZE       64
#define WEAPON_CMD_SIZE         32


#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define IS_SURVIVOR_ALIVE(%1)   (IS_VALID_INGAME(%1) && IS_SURVIVOR(%1) && IsPlayerAlive(%1))

enum struct VoteItem
{
	char title[WEAPON_TITLE_SIZE];
	char name[WEAPON_NAME_SIZE];
}

Handle g_hMapVoteItems = INVALID_HANDLE;

VoteItem g_tVotingItem;

bool
	g_bReadyUpAvailable = false,
	g_bRoundIsLive = false;


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

	g_hMapVoteItems = CreateTrie();

	ReadMapVoteItems();
	
	HookEvent("versus_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

/**
  * Loads dictionary files. On failure, stops the plugin execution.
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
 * Called when the plugin is about to be unloaded.
 * 
 * @noreturn
 */
public void OnPluginEnd()
{
	CloseHandle(g_hMapVoteItems);
}

/**
  * File reader. Opens and reads lines in config/weapon_vote.ini.
  *
  * @noreturn
  */
void ReadMapVoteItems()
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
	VoteItem tVoteItem;
	int iPos;

	iPos = BreakString(sLine, tVoteItem.name, sizeof(tVoteItem.name));
	iPos += BreakString(sLine[iPos], tVoteItem.title, sizeof(tVoteItem.title));

	char sCmd[WEAPON_CMD_SIZE]; BreakString(sLine[iPos], sCmd, sizeof(sCmd));

	SetTrieArray(g_hMapVoteItems, sCmd, tVoteItem, sizeof(tVoteItem));
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

	if (sArgs[0] != '/' && sArgs[0] != '!') {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE];
	strcopy(sCmd, sizeof(sCmd), sArgs[1]);

	VoteItem tVoteItem;

	if (GetTrieArray(g_hMapVoteItems, sCmd, tVoteItem, sizeof(tVoteItem))) {
		StartVote(iClient, tVoteItem);
	}

	return Plugin_Handled;
}

/**
  * Called when a client is sending a command.
  *
  * @param iClient			Client index.
  * @param iArgs			Number of arguments.
  *
  * @return Plugin_Handled | Plugin_Continue
  */
public Action OnClientCommand(int iClient, int iArgs)
{
	if (!IS_VALID_CLIENT(iClient) || IsFakeClient(iClient)) {
		return Plugin_Handled;
	}

	char sArgs[64];
  	GetCmdArg(0, sArgs, sizeof(sArgs));

	if (sArgs[0] != 's' && sArgs[1] != 'm' && sArgs[2] != '_') {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE];
	strcopy(sCmd, sizeof(sCmd), sArgs[3]);

	VoteItem tVoteItem;

	if (GetTrieArray(g_hMapVoteItems, sCmd, tVoteItem, sizeof(tVoteItem))) {
		StartVote(iClient, tVoteItem);
	}

	return Plugin_Handled;
}

public void StartVote(int iClient, VoteItem tVoteItem) 
{
	if (!NativeVotes_IsNewVoteAllowed())
	{
		CPrintToChat(iClient, "%T", "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	if (g_bReadyUpAvailable && !IsInReady())
	{
		CPrintToChat(iClient, "%T", "LEFT_READYUP", iClient);
		return;
	} 

	if (!g_bReadyUpAvailable && g_bRoundIsLive)
	{
		CPrintToChat(iClient, "%T", "ROUND_LIVE", iClient);
		return;
	}

	if (!IS_SURVIVOR(iClient))
	{
		CPrintToChat(iClient, "%T", "ONLY_SURVIVOR", iClient);
		return;
	}

	g_tVotingItem = tVoteItem;

	int iTotalPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer++)
	{
		if (!IsClientInGame(iPlayer) || IsFakeClient(iPlayer) || (GetClientTeam(iPlayer) != VOTE_TEAM)) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo);
	hVote.Initiator = iClient;
	hVote.Team = VOTE_TEAM;
	hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

public Action HandlerVote(NativeVote hVote, VoteAction iAction, int iParam1, int iParam2)
{
	switch (iAction)
	{
		case VoteAction_Start:
		{
			CPrintToChatAll("%t", "VOTE_START", iParam1, g_tVotingItem.title);

			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(false);
			}
		}

		case VoteAction_Display:
		{
			hVote.SetDetails("%T", "VOTE_TITLE", iParam1, hVote.Initiator, g_tVotingItem.title);

			return Plugin_Changed;
		}
		
		case VoteAction_Cancel: {
			hVote.DisplayFail();
		}
		
		case VoteAction_Finish:
		{
			if (!IS_SURVIVOR_ALIVE(hVote.Initiator)
				|| (!g_bReadyUpAvailable && g_bRoundIsLive)
				|| (g_bReadyUpAvailable && !IsInReady())) {
				hVote.DisplayFail();
				return Plugin_Continue;
			}

			if (iParam1 == NATIVEVOTES_VOTE_NO)
			{
				hVote.DisplayFail();

				CPrintToChatAll("%t", "VOTE_FAIL", hVote.Initiator, g_tVotingItem.title);
			}

			else
			{
				hVote.DisplayPass();

				GivePlayerItem(hVote.Initiator, g_tVotingItem.name);

				CPrintToChatAll("%t", "VOTE_PASS", hVote.Initiator, g_tVotingItem.title);
			}
		}

		case VoteAction_End:
		{
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(true);
			}

			hVote.Close();
		}
	}

	return Plugin_Continue;
}
