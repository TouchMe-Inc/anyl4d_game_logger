#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#undef REQUIRE_PLUGIN
#include <config_manager>
#define REQUIRE_PLUGIN

public Plugin myinfo = {
    name        = "Game Logger",
    author      = "TouchMe",
    description = "",
    version     = "build_0001",
    url         = ""
};


#define LIB_CONFIG_MANAGER "config_manager"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define AWARD_HUNTER_PUNTER        21
#define AWARD_TONGUE_TWISTER       27
#define AWARD_PROTECT_TEAMMATE     67
#define AWARD_NO_DEATH_ON_TANK     80
#define AWARD_KILLED_ALL_SURVIVORS 136

#define MAX_LOG_WEAPONS 27
#define MAX_WEAPON_LEN 16


enum WeaponStats
{
    WeaponStats_Shots,
    WeaponStats_Hits,
    WeaponStats_Kills,
    WeaponStats_HS,
    WeaponStats_TeamKill,
    WeaponStats_Damage
}

char g_szWeaponList[][] = {
    "autoshotgun",
    "rifle",
    "pumpshotgun",
    "smg",
    "dual_pistols",
    "pipe_bomb",
    "hunting_rifle",
    "pistol",
    "prop_minigun",
    "tank_claw",
    "hunter_claw",
    "smoker_claw",
    "boomer_claw",
    "smg_silenced",     // l4d2 start 14 [13]
    "pistol_magnum",
    "rifle_ak47",
    "rifle_desert",
    "shotgun_chrome",
    "shotgun_spas",
    "sniper_military",
    "rifle_sg552",
    "smg_mp5",
    "sniper_awp",
    "sniper_scout",
    "jockey_claw",
    "splitter_claw",
    "charger_claw"
};

char g_szTeamList[][] = {
    "Unassigned",
    "Spectator",
    "Survivor",
    "Infected"
};


int  g_iWeaponStats[MAXPLAYERS + 1][MAX_LOG_WEAPONS][WeaponStats];

int g_iActiveWeaponOffset = 0;

bool g_bIsL4D2 = false;

StringMap g_smWeaponIndex = null;


char g_szMapName[64];

ConVar g_cvGamemode = null;
char g_szGamemode[32];


bool g_bConfigManagerAvailable = false;
char g_szConfigPath[32];

/**
  * Global event. Called when all plugins loaded.
  */
public void OnAllPluginsLoaded() {
    g_bConfigManagerAvailable = LibraryExists(LIB_CONFIG_MANAGER);
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName     Library name
  */
public void OnLibraryRemoved(const char[] sName)
{
    if (StrEqual(sName, LIB_CONFIG_MANAGER)) {
        g_bConfigManagerAvailable = false;
    }
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName     Library name
  */
public void OnLibraryAdded(const char[] sName)
{
    if (StrEqual(sName, LIB_CONFIG_MANAGER)) {
        g_bConfigManagerAvailable = true;
    }
}

public APLRes AskPluginLoad2(Handle hPlugin, bool bLate, char[] szError, int iErrMax)
{
    switch (GetEngineVersion())
    {
        case Engine_Left4Dead: g_bIsL4D2 = false;
        case Engine_Left4Dead2: g_bIsL4D2 = true;
        default: {
            strcopy(szError, iErrMax, "Plugin only supports Left 4 Dead 1/2");
            return APLRes_SilentFailure;
        }
    }

    return APLRes_Success;
}

public void OnPluginStart()
{
    HookEvent("survivor_rescued",            Event_RescueSurvivor);
    HookEvent("heal_success",                Event_Heal);
    HookEvent("revive_success",              Event_Revive);
    HookEvent("witch_harasser_set",          Event_StartleWitch);
    HookEvent("lunge_pounce",                Event_Pounce);
    HookEvent("player_now_it",               Event_Boomered);
    HookEvent("friendly_fire",               Event_FF);
    HookEvent("witch_killed",                Event_WitchKilled);
    HookEvent("award_earned",                Event_Award);

    if (g_bIsL4D2)
    {
        HookEvent("defibrillator_used",      Event_DefibrillatorUsed);
        HookEvent("adrenaline_used",         Event_AdrenalineUsed);
        HookEvent("pills_used",              Event_PillsUsed);
        HookEvent("jockey_ride",             Event_JockeyRide);
        HookEvent("charger_pummel_start",    Event_ChargerPummelStart);
        HookEvent("vomit_bomb_tank",         Event_VomitBombTank);
        HookEvent("scavenge_match_finished", Event_ScavengeEnd);
        HookEvent("versus_match_finished",   Event_VersusEnd);
    }

    HookEvent("weapon_fire",                 Event_PlayerShoot);
    HookEvent("weapon_fire_on_empty",        Event_PlayerShoot);
    HookEvent("player_hurt",                 Event_PlayerHurt);
    HookEvent("infected_hurt",               Event_InfectedHurt);
    HookEvent("player_death",                Event_PlayerDeathPre,   EventHookMode_Pre);
    HookEvent("player_death",                Event_PlayerDeath,      EventHookMode_Post);
    HookEvent("player_spawn",                Event_PlayerSpawn);
    HookEvent("round_end_message",           Event_RoundEnd,         EventHookMode_PostNoCopy);
    HookEvent("player_disconnect",           Event_PlayerDisconnect, EventHookMode_Pre);

    g_cvGamemode = FindConVar("mp_gamemode");
    GetConVarString(g_cvGamemode, g_szGamemode, sizeof g_szGamemode);
    HookConVarChange(g_cvGamemode, CvChange_GameMode);

    g_iActiveWeaponOffset = FindSendPropInfo("CTerrorPlayer", "m_hActiveWeapon");
    g_smWeaponIndex = CreateWeaponIndexMap();
    strcopy(g_szConfigPath, sizeof g_szConfigPath, "none");
    
    AddGameLogHook(LogHook);
}

public void OnMapInit(const char[] szMapName) {
    strcopy(g_szMapName, sizeof g_szMapName, szMapName);
}

void CvChange_GameMode(ConVar convar, const char[] szOldGamemode, const char[] szGamemode) {
    strcopy(g_szGamemode, sizeof g_szGamemode, szGamemode);
}

public void ConfigManager_OnLoadConfig() {
    ConfigManager_GetConfigPath(g_szConfigPath, sizeof g_szConfigPath);
}

public void ConfigManager_OnUnloadConfig() {
    strcopy(g_szConfigPath, sizeof g_szConfigPath, "none");
}

Action LogHook(const char[] szMessage)
{
    if (g_bConfigManagerAvailable) {
        LogToGame("[map=%s;gamemode=%s;config=%s] %s", g_szMapName, g_szGamemode, g_szConfigPath, szMessage);
    } else {
        LogToGame("[map=%s;gamemode=%s] %s", g_szMapName, g_szGamemode, szMessage);
    }

    return Plugin_Handled;
}

public void OnClientPutInServer(int iClient) {
    ResetWeaponStats(iClient);
}

// "local"         "1"             // don't network this, its way too spammy
// "userid"        "short"
// "weapon"        "string"        // used weapon name
// "weaponid"      "short"         // used weapon ID
// "count"         "short"         // number of bullets
void Event_PlayerShoot(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iAttacker = GetClientOfUserId(event.GetInt("userid"));
    if (iAttacker <= 0) {
        return;
    }

    char szWeapon[MAX_WEAPON_LEN];
    event.GetString("weapon", szWeapon, sizeof(szWeapon));

    int iWeaponIndex = GetWeaponIndex(szWeapon);
    if (iWeaponIndex > -1) {
        g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_Shots]++;
    }
}

// "local"         "1"             // Not networked
// "userid"        "short"         // user ID who was hurt
// "attacker"      "short"         // user id who attacked
// "attackerentid" "long"          // entity id who attacked, if attacker not a player, and userid therefore invalid
// "health"        "short"         // remaining health points
// "armor"         "byte"          // remaining armor points
// "weapon"        "string"        // weapon name attacker used, if not the world
// "dmg_health"    "short"         // damage done to health
// "dmg_armor"     "byte"          // damage done to armor
// "hitgroup"      "byte"          // hitgroup that was damaged
// "type"          "long"          // damage type
void Event_PlayerHurt(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iAttacker  = GetClientOfUserId(event.GetInt("attacker"));
    if (iAttacker <= 0) {
        return;
    }

    char szWeapon[MAX_WEAPON_LEN];
    GetEventString(event, "weapon", szWeapon, sizeof(szWeapon));

    int iWeaponIndex = GetWeaponIndex(szWeapon);
    if (iWeaponIndex > -1)
    {
        g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_Hits]++;
        g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_Damage] += event.GetInt("dmg_health");
    }

    else if (!strcmp(szWeapon, "insect_swarm"))
    {
        int iVictim = GetClientOfUserId(event.GetInt("userid"));

        if (IsValidPlayer(iVictim) && GetClientTeam(iVictim) == TEAM_SURVIVOR && !IsClientIncapacitated(iVictim))
            Log_PlayerToPlayerEvent(iAttacker, iVictim, "triggered", "spit_hurt", true);
    }
}

// "local"         "1"             // don't network this, its way too spammy
// "attacker"      "short"         // player userid who attacked
// "entityid"      "long"          // entity id of infected
// "hitgroup"      "byte"          // hitgroup that was damaged
// "amount"        "short"         // how much damage was done
// "type"          "long"          // damage type
void Event_InfectedHurt(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iAttacker  = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidPlayer(iAttacker)) {
        return;
    }

    char szWeapon[MAX_WEAPON_LEN];
    GetClientWeapon(iAttacker, szWeapon, sizeof(szWeapon));

    int iWeaponIndex = GetWeaponIndex(szWeapon[7]);
    if (iWeaponIndex > -1)
    {
        g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_Hits]++;
        g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_Damage] += event.GetInt("amount");
    }
}

void Event_PlayerDeathPre(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iAttacker = GetClientOfUserId(event.GetInt("attacker"));

    if (g_bIsL4D2 && IsValidPlayer(iAttacker))
    {
        char szWeapon[32];
        GetEventString(event, "weapon", szWeapon, sizeof szWeapon);

        if (strncmp(szWeapon, "melee", 5) == 0)
        {
            int iWeapon = GetEntDataEnt2(iAttacker, g_iActiveWeaponOffset);
            if (IsValidEdict(iWeapon))
            {
                // They have time to switch weapons after the kill before the death event
                GetEdictClassname(iWeapon, szWeapon, sizeof(szWeapon));

                if (strncmp(szWeapon[7], "melee", 5) == 0)
                {
                    GetEntPropString(iWeapon, Prop_Data, "m_strMapSetScriptName", szWeapon, sizeof szWeapon);
                    event.SetString("weapon", szWeapon);
                }
            }
        }
    }
}

// "userid"        "short"         // user ID who died
// "entityid"      "long"          // entity ID who died, userid should be used first, to get the dead Player.  Otherwise, it is not a player, so use this.         $
// "attacker"      "short"         // user ID who killed
// "attackername"  "string"        // What type of zombie, so we don't have zombie names
// "attackerentid" "long"          // if killer not a player, the entindex of who killed.  Again, use attacker first
// "weapon"        "string"        // weapon name killer used
// "headshot"      "bool"          // signals a headshot
// "attackerisbot" "bool"          // is the attacker a bot
// "victimname"    "string"        // What type of zombie, so we don't have zombie names
// "victimisbot"   "bool"          // is the victim a bot
// "abort"         "bool"          // did the victim abort
// "type"          "long"          // damage type
// "victim_x"      "float"
// "victim_y"      "float"
// "victim_z"      "float"
void Event_PlayerDeath(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iVictim   = GetClientOfUserId(event.GetInt("userid"));
    int iAttacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidPlayer(iAttacker) || !IsValidPlayer(iVictim)) {
        return;
    }

    char szWeapon[MAX_WEAPON_LEN];
    GetEventString(event, "weapon", szWeapon, sizeof szWeapon);

    int iWeaponIndex = GetWeaponIndex(szWeapon);
    if (iWeaponIndex > -1)
    {
        g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_Kills]++;
        if (event.GetBool("headshot")) {
            g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_HS]++;
        }

        if (GetClientTeam(iAttacker) == GetClientTeam(iVictim)) {
            g_iWeaponStats[iAttacker][iWeaponIndex][WeaponStats_TeamKill]++;
        }
        DumpWeaponStats(iVictim);
    }
}

void Event_RoundEnd(Event event, const char[] szEventName, bool bDontBroadcast)
{
    DumpWeaponStatsAll();
}

// "userid"        "short"         // user ID on server
void Event_PlayerSpawn(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(event.GetInt("userid"));
    if (iClient > 0) ResetWeaponStats(iClient);
}

void Event_PlayerDisconnect(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(event.GetInt("userid"));

    if (IsValidPlayer(iClient)) {
        DumpWeaponStats(iClient);
        ResetWeaponStats(iClient);
    }
}

void Event_RescueSurvivor(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("rescuer"));
    if (iPlayer <= 0) return;
    Log_PlayerEvent(iPlayer, "triggered", "rescued_survivor", true);
}

void Event_Heal(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("userid"));
    if (iPlayer <= 0) return;
    if (iPlayer == GetClientOfUserId(event.GetInt("subject"))) return;
    Log_PlayerEvent(iPlayer, "triggered", "healed_teammate", true);
}

void Event_Revive(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("userid"));
    if (iPlayer <= 0) return;
    Log_PlayerEvent(iPlayer, "triggered", "revived_teammate", true);
}

void Event_StartleWitch(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("userid"));
    if (iPlayer > 0 && event.GetBool("first")) Log_PlayerEvent(iPlayer, "triggered", "startled_witch", true);
}

void Event_Pounce(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("userid"));
    int iVictim = GetClientOfUserId(event.GetInt("victim"));
    if (iVictim > 0) Log_PlayerToPlayerEvent(iPlayer, iVictim, "triggered", "pounce", true);
    else             Log_PlayerEvent(iPlayer, "triggered", "pounce", true);
}

void Event_Boomered(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("attacker"));
    int iVictim = GetClientOfUserId(event.GetInt("userid"));
    if (iPlayer > 0 && event.GetBool("by_boomer")) {
        if (iVictim > 0) Log_PlayerToPlayerEvent(iPlayer, iVictim, "triggered", "vomit", true);
        else             Log_PlayerEvent(iPlayer, "triggered", "vomit", true);
    }
}

void Event_FF(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("attacker"));
    int iVictim = GetClientOfUserId(event.GetInt("victim"));
    if (iPlayer > 0 && iPlayer == GetClientOfUserId(event.GetInt("guilty"))) {
        if (iVictim > 0) Log_PlayerToPlayerEvent(iPlayer, iVictim, "triggered", "friendly_fire", true);
        else             Log_PlayerEvent(iPlayer, "triggered", "friendly_fire", true);
    }
}

void Event_WitchKilled(Event event, const char[] szEventName, bool bDontBroadcast) {
    if (event.GetBool("oneshot")) Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "crowned", true);
}

void Event_DefibrillatorUsed(Event event, const char[] szEventName, bool bDontBroadcast) {
    Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "defibrillated_teammate", true);
}

void Event_AdrenalineUsed(Event event, const char[] szEventName, bool bDontBroadcast) {
    Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "used_adrenaline", true);
}

void Event_PillsUsed(Event event, const char[] szEventName, bool bDontBroadcast) {
    Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "used_pills", true);
}

void Event_JockeyRide(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("userid"));

    if (iPlayer <= 0) return;

    int iVictim = GetClientOfUserId(event.GetInt("victim"));

    if (iVictim > 0) Log_PlayerToPlayerEvent(iPlayer, iVictim, "triggered", "jockey_ride", true);
    else             Log_PlayerEvent(iPlayer, "triggered", "jockey_ride", true);
}

void Event_ChargerPummelStart(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(event.GetInt("userid"));
    int iVictim = GetClientOfUserId(event.GetInt("victim"));

    if (iVictim > 0) Log_PlayerToPlayerEvent(iPlayer, iVictim, "triggered", "charger_pummel", true);
    else             Log_PlayerEvent(iPlayer, "triggered", "charger_pummel", true);
}

void Event_VomitBombTank(Event event, const char[] szEventName, bool bDontBroadcast) {
    Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "bilebomb_tank", true);
}

void Event_ScavengeEnd(Event event, const char[] szEventName, bool bDontBroadcast) {
    Log_TeamEvent(GetEventInt(event, "winners"), "triggered", "Scavenge_Win");
}

void Event_VersusEnd(Event event, const char[] szEventName, bool bDontBroadcast) {
    Log_TeamEvent(GetEventInt(event, "winners"), "triggered", "Versus_Win");
}

// "userid"         "short"         // player who earned the award
// "entityid"       "long"          // client likes ent id
// "subjectentid"   "long"          // entity id of other party in the award, if any
// "award"          "short"         // id of award earned
void Event_Award(Event event, const char[] szEventName, bool bDontBroadcast)
{
    switch (GetEventInt(event, "award"))
    {
        case AWARD_HUNTER_PUNTER:
            Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "hunter_punter", true);

        case AWARD_TONGUE_TWISTER:
            Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "tounge_twister", true);

        case AWARD_PROTECT_TEAMMATE:
            Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "protect_teammate", true);

        case AWARD_NO_DEATH_ON_TANK:
            Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "no_death_on_tank", true);

        case AWARD_KILLED_ALL_SURVIVORS:
            Log_PlayerEvent(GetClientOfUserId(event.GetInt("userid")), "triggered", "killed_all_survivors", true);
    }
}

void Log_PlayerEvent(int iClient, const char[] szVerb, const char[] szEvent, bool bDisplayLocation = false)
{
    if (IsValidPlayer(iClient))
    {
        LogToGame("\"%s\" %s \"%s\"", GetPlayerInfo(iClient, bDisplayLocation), szVerb, szEvent);
    }
}

void Log_PlayerToPlayerEvent(int iClient, int iVictim, const char[] szVerb, const char[] szEvent, bool bDisplayLocation = false)
{
    if (IsValidPlayer(iClient) && IsValidPlayer(iVictim))
    {
        LogToGame("\"%s\" %s \"%s\" against \"%s\"", GetPlayerInfo(iClient, bDisplayLocation), szVerb, szEvent, GetPlayerInfo(iVictim, bDisplayLocation));
    }
}

void Log_TeamEvent(int iTeam, const char[] szVerb, const char[] szEvent)
{
    if (iTeam >= 0) {
        LogToGame("Team \"%s\" %s \"%s\"", g_szTeamList[iTeam], szVerb, szEvent);
    }
}

any[] GetPlayerInfo(int iClient, bool bWithLocation = false)
{
    char szBuffer[128];

    char szAuthId[MAX_AUTHID_LENGTH];
    GetClientAuthIdSafe(iClient, szAuthId, sizeof(szAuthId));

    if (bWithLocation == true)
    {
        float vOrigin[3];
        GetClientAbsOrigin(iClient, vOrigin);

        float vAngles[3];
        GetClientEyeAngles(iClient, vAngles);

        FormatEx(
            szBuffer,
            sizeof szBuffer,
            "%N<%d><%s><%s><setpos_exact %.2f %.2f %.2f; setang %.2f %.2f %.2f>",
            iClient,
            GetClientUserId(iClient),
            szAuthId,
            g_szTeamList[GetClientTeam(iClient)],
            vOrigin[0], vOrigin[1], vOrigin[2],
            vAngles[0], vAngles[1], vAngles[2]
        );
    }
    else
    {
        FormatEx(szBuffer, sizeof szBuffer, "%N<%d><%s><%s>", iClient, GetClientUserId(iClient), szAuthId, g_szTeamList[GetClientTeam(iClient)]);
    }

    return szBuffer;
}

void GetClientAuthIdSafe(int client, char[] buffer, int maxlen)
{
    if (!GetClientAuthId(client, AuthId_Engine, buffer, maxlen, false)) {
        strcopy(buffer, maxlen, "UNKNOWN");
    }
}

StringMap CreateWeaponIndexMap()
{
    StringMap smWeaponIndex = new StringMap();

    for (int i = 0; i < sizeof(g_szWeaponList); i++) {
        smWeaponIndex.SetValue(g_szWeaponList[i], i);
    }

    return smWeaponIndex;
}

int GetWeaponIndex(const char[] szWeaponName)
{
    int iIdx = -1;
    g_smWeaponIndex.GetValue(szWeaponName, iIdx);
    return iIdx;
}

void DumpWeaponStats(int iClient)
{
    char szPlayerInfo[128];
    FormatEx(szPlayerInfo, sizeof szPlayerInfo, "%s", GetPlayerInfo(iClient));

    for (int i = 0; i < sizeof(g_szWeaponList); i++)
    {
        if (g_iWeaponStats[iClient][i][WeaponStats_Shots] == 0) {
            continue;
        }

        LogToGame("\"%s\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\")", szPlayerInfo, g_szWeaponList[i], g_iWeaponStats[iClient][i][WeaponStats_Shots], g_iWeaponStats[iClient][i][WeaponStats_Hits], g_iWeaponStats[iClient][i][WeaponStats_Kills], g_iWeaponStats[iClient][i][WeaponStats_HS], g_iWeaponStats[iClient][i][WeaponStats_TeamKill], g_iWeaponStats[iClient][i][WeaponStats_Damage]);
        ResetWeaponStatsByIndex(iClient, i);
    }
}

void DumpWeaponStatsAll()
{
    for (int iClient = 1; iClient <= MaxClients; iClient++)
    {
        if (!IsClientInGame(iClient)) {
            continue;
        }

        DumpWeaponStats(iClient);
    }
}

void ResetWeaponStats(int iClient)
{
    for (int i = 0; i < sizeof(g_szWeaponList); i++)
    {
        ResetWeaponStatsByIndex(iClient, i);
    }
}

void ResetWeaponStatsByIndex(int iClient, int iWeaponIndex)
{
    g_iWeaponStats[iClient][iWeaponIndex][WeaponStats_Shots]    = 0;
    g_iWeaponStats[iClient][iWeaponIndex][WeaponStats_Hits]     = 0;
    g_iWeaponStats[iClient][iWeaponIndex][WeaponStats_Kills]    = 0;
    g_iWeaponStats[iClient][iWeaponIndex][WeaponStats_HS]       = 0;
    g_iWeaponStats[iClient][iWeaponIndex][WeaponStats_TeamKill] = 0;
    g_iWeaponStats[iClient][iWeaponIndex][WeaponStats_Damage]   = 0;
}

bool IsValidPlayer(int iClient) {
    return (IsValidClientIndex(iClient) && IsClientInGame(iClient));
}

bool IsValidClientIndex(int iClient) {
    return (iClient > 0 && iClient <= MaxClients);
}

bool IsClientIncapacitated(int iClient) {
    return view_as<bool>(GetEntProp(iClient, Prop_Send, "m_isIncapacitated"));
}
