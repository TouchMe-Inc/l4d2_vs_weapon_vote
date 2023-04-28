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
	name = "VersusWeaponVote",
	author = "TouchMe",
	description = "Issues weapons based on voting results",
	version = "build_0003",
	url = "https://github.com/TouchMe-Inc/l4d2_vs_weapon_vote"
};


// Libs
#define LIB_READY              "readyup"

#define TRANSLATIONS            "vs_weapon_vote.phrases"
#define CONFIG_FILEPATH         "configs/vs_weapon_vote.txt"

#define TEAM_SURVIVOR           2
#define TEAM_INFECTED           3

#define VOTE_TIME               15

#define WEAPON_NAME_SIZE        32
#define WEAPON_CMD_SIZE         32


// Vars

enum ConfigSection
{
	ConfigSection_None,
	ConfigSection_Weapons,
	ConfigSection_Weapon
}

ConfigSection g_tConfigSection = ConfigSection_None;

char
	g_sConfigSection[WEAPON_NAME_SIZE],
	g_sWeaponName[WEAPON_NAME_SIZE];

bool
	g_bReadyUpAvailable = false,
	g_bRoundIsLive = false;

Handle g_hWeapons = INVALID_HANDLE;


/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded() {
	g_bReadyUpAvailable = LibraryExists(LIB_READY);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName 			Library name.
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
  * Called when the map loaded.
  */
public void OnMapStart() {
	g_bRoundIsLive = false;
}

/**
 * Called when the plugin is fully initialized and all known external references are resolved.
 */
public void OnPluginStart()
{
	g_hWeapons = CreateTrie();

	LoadTranslations(TRANSLATIONS);

	LoadConfig(CONFIG_FILEPATH);

	RegCmds();

	HookEvent("versus_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

void RegCmds()
{
	Handle hSnapshot = CreateTrieSnapshot(g_hWeapons);

	int iSize = TrieSnapshotLength(hSnapshot);

	char sCmd[WEAPON_CMD_SIZE];

	for(int iIndex = 0; iIndex < iSize; iIndex ++)
	{
		GetTrieSnapshotKey(hSnapshot, iIndex, sCmd, sizeof(sCmd));
		RegConsoleCmd(sCmd, Cmd_StartVote);
	}

	CloseHandle(hSnapshot);
}

public Action Cmd_StartVote(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)) {
		return Plugin_Continue;
	}

	char sCmd[WEAPON_CMD_SIZE];
	GetCmdArg(0, sCmd, sizeof(sCmd));

	char sWeaponName[WEAPON_NAME_SIZE];

	if (GetTrieString(g_hWeapons, sCmd, sWeaponName, sizeof(sWeaponName))) {
		StartVote(iClient, sWeaponName);
	}

	return Plugin_Continue;
}

/**
 * Called when the plugin is about to be unloaded.
 */
public void OnPluginEnd() {
	CloseHandle(g_hWeapons);
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

public void StartVote(int iClient, const char[] sWeaponName)
{
	if (!NativeVotes_IsNewVoteAllowed())
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_COULDOWN", iClient, NativeVotes_CheckVoteDelay());
		return;
	}

	if (g_bReadyUpAvailable && !IsInReady())
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "LEFT_READYUP", iClient);
		return;
	}

	if (!g_bReadyUpAvailable && g_bRoundIsLive)
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "ROUND_LIVE", iClient);
		return;
	}

	if (!IsClientSurvivor(iClient) || !IsPlayerAlive(iClient))
	{
		CPrintToChat(iClient, "%T%T", "TAG", iClient, "ONLY_ALIVE_SURVIVOR", iClient);
		return;
	}

	strcopy(g_sWeaponName, sizeof(g_sWeaponName), sWeaponName);

	int iTotalPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int iPlayer = 1; iPlayer <= MaxClients; iPlayer ++)
	{
		if (!IsClientInGame(iPlayer)
		|| IsFakeClient(iPlayer)
		|| !IsClientInfected(iPlayer)) {
			continue;
		}

		iPlayers[iTotalPlayers++] = iPlayer;
	}

	NativeVote hVote = new NativeVote(HandlerVote, NativeVotesType_Custom_YesNo);
	hVote.Initiator = iClient;
	hVote.Team = TEAM_INFECTED;
	hVote.DisplayVote(iPlayers, iTotalPlayers, VOTE_TIME);
}

public Action HandlerVote(NativeVote hVote, VoteAction iAction, int iParam1, int iParam2)
{
	switch (iAction)
	{
		case VoteAction_Start:
		{
			char sDisplayName[64];

			for (int iClient = 1; iClient <= MaxClients; iClient ++)
			{
				if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
					continue;
				}

				FormatEx(sDisplayName, sizeof(sDisplayName), "%T", g_sWeaponName, iClient);

				CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_START", iClient, iParam1, sDisplayName);
			}

			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(false);
			}
		}

		case VoteAction_Display:
		{
			char sDisplayName[64];

			FormatEx(sDisplayName, sizeof(sDisplayName), "%T", g_sWeaponName, iParam1);

			hVote.SetDetails("%T", "VOTE_TITLE", iParam1, hVote.Initiator, sDisplayName);

			return Plugin_Changed;
		}

		case VoteAction_Cancel: {
			hVote.DisplayFail();
		}

		case VoteAction_Finish:
		{
			if (!IsClientSurvivor(hVote.Initiator)
				|| !IsPlayerAlive(hVote.Initiator)
				|| (!g_bReadyUpAvailable && g_bRoundIsLive)
				|| (g_bReadyUpAvailable && !IsInReady())) {
				hVote.DisplayFail();
				return Plugin_Continue;
			}

			if (iParam1 == NATIVEVOTES_VOTE_NO)
			{
				hVote.DisplayFail();

				char sDisplayName[64];

				for (int iClient = 1; iClient <= MaxClients; iClient ++)
				{
					if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
						continue;
					}

					FormatEx(sDisplayName, sizeof(sDisplayName), "%T", g_sWeaponName, iClient);

					CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_FAIL", iClient, hVote.Initiator, sDisplayName);
				}
			}

			else
			{
				hVote.DisplayPass();

				GivePlayerItem(hVote.Initiator, g_sWeaponName);

				char sDisplayName[64];

				for (int iClient = 1; iClient <= MaxClients; iClient ++)
				{
					if (!IsClientInGame(iClient) || IsFakeClient(iClient)) {
						continue;
					}

					FormatEx(sDisplayName, sizeof(sDisplayName), "%T", g_sWeaponName, iClient);

					CPrintToChat(iClient, "%T%T", "TAG", iClient, "VOTE_PASS", iClient, hVote.Initiator, sDisplayName);
				}
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

bool LoadConfig(const char[] sPathToConfig)
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, sPathToConfig);

	if (!FileExists(sPath)) {
		SetFailState("File %s not found", sPath);
	}

	Handle hParser = SMC_CreateParser();

	int iLine = 0;
	int iColumn = 0;

	SMC_SetReaders(hParser, Parser_EnterSection, Parser_KeyValue, Parser_LeaveSection);

	SMCError hResult = SMC_ParseFile(hParser, sPath, iLine, iColumn);
	
	CloseHandle(hParser);

	if (hResult != SMCError_Okay)
	{
		char sError[128];
		SMC_GetErrorString(hResult, sError, sizeof(sError));
		LogError("%s on line %d, col %d of %s", sError, iLine, iColumn, sPath);
	}

	return (hResult == SMCError_Okay);
}

public SMCResult Parser_EnterSection(SMCParser smc, const char[] sSection, bool opt_quotes)
{
	if (StrEqual(sSection, "Weapons")) {
		g_tConfigSection = ConfigSection_Weapons;
	}

	else if (g_tConfigSection == ConfigSection_Weapons)
	{
		g_tConfigSection = ConfigSection_Weapon;
		strcopy(g_sConfigSection, sizeof(g_sConfigSection), sSection);
	}

	return SMCParse_Continue;
}

public SMCResult Parser_KeyValue(SMCParser smc,
									const char[] sKey,
									const char[] sValue,
									bool key_quotes,
									bool value_quotes)
{
	if (g_tConfigSection != ConfigSection_Weapon) {
		return SMCParse_Continue;
	}

	if (StrEqual(sKey, "cmd")) {
		SetTrieString(g_hWeapons, sValue, g_sConfigSection);
	}

	return SMCParse_Continue;
}

public SMCResult Parser_LeaveSection(SMCParser smc)
{
	if (g_tConfigSection == ConfigSection_Weapon) {
		g_tConfigSection = ConfigSection_Weapons;
	}

	return SMCParse_Continue;
}

bool IsValidClient(int iClient) {
	return (iClient > 0 && iClient <= MaxClients);
}

bool IsClientSurvivor(int iClient) {
	return (GetClientTeam(iClient) == TEAM_SURVIVOR);
}

bool IsClientInfected(int iClient) {
	return (GetClientTeam(iClient) == TEAM_INFECTED);
}
