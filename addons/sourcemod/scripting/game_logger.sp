#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>


public Plugin myinfo = {
    name        = "Game Logger",
    author      = "psychonic, TouchMe",
    description = "",
    version     = "build_0001",
    url         = ""
};


#define HITGROUP_GENERIC   0
#define HITGROUP_HEAD      1
#define HITGROUP_CHEST     2
#define HITGROUP_STOMACH   3
#define HITGROUP_LEFTARM   4
#define HITGROUP_RIGHTARM  5
#define HITGROUP_LEFTLEG   6
#define HITGROUP_RIGHTLEG  7

#define LOG_HIT_OFFSET     7 

#define LOG_HIT_SHOTS      0
#define LOG_HIT_HITS       1
#define LOG_HIT_KILLS      2
#define LOG_HIT_HEADSHOTS  3
#define LOG_HIT_TEAMKILLS  4
#define LOG_HIT_DAMAGE     5
#define LOG_HIT_DEATHS     6
#define LOG_HIT_GENERIC    7
#define LOG_HIT_HEAD       8
#define LOG_HIT_CHEST      9
#define LOG_HIT_STOMACH    10
#define LOG_HIT_LEFTARM    11
#define LOG_HIT_RIGHTARM   12
#define LOG_HIT_LEFTLEG    13
#define LOG_HIT_RIGHTLEG   14

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3



#define AWARD_HUNTER_PUNTER        21
#define AWARD_TONGUE_TWISTER       27
#define AWARD_PROTECT_TEAMMATE     67
#define AWARD_NO_DEATH_ON_TANK     80
#define AWARD_KILLED_ALL_SURVIVORS 136


#define MAX_LOG_WEAPONS 27
#define MAX_WEAPON_LEN 16

int  g_iWeaponStats[MAXPLAYERS + 1][MAX_LOG_WEAPONS][15];
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


int g_iActiveWeaponOffset;

bool g_bIsL4D2;

char g_szTeamList[4][32];

StringMap g_smWeaponTrie;


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
    CreatePopulateWeaponTrie();

    HookEvent("player_death",                Event_PlayerDeathPre, EventHookMode_Pre);
    
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
        HookEvent("defibrillator_used",      Event_Defib);
        HookEvent("adrenaline_used",         Event_Adrenaline);
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
    HookEvent("player_death",                Event_PlayerDeath);
    HookEvent("player_spawn",                Event_PlayerSpawn);
    HookEvent("round_end_message",           Event_RoundEnd,         EventHookMode_PostNoCopy);
    HookEvent("player_disconnect",           Event_PlayerDisconnect, EventHookMode_Pre);

    
    CreateTimer(60.0, FlushWeaponLogs, .flags = TIMER_REPEAT);

    CreateTimer(1.0, Timer_LogMap);

    g_iActiveWeaponOffset = FindSendPropInfo("CTerrorPlayer", "m_hActiveWeapon");
}

public void OnMapStart()
{
    CacheTeams();
}

void CreatePopulateWeaponTrie()
{
    g_smWeaponTrie = new StringMap();

    for (int i = 0; i < sizeof(g_szWeaponList); i++) {
        g_smWeaponTrie.SetValue(g_szWeaponList[i], i);
    }
}

void DumpPlayerStats(int iClient)
{
    if (!IsClientInGame(iClient)) {
        return;
    }

    char szPlayerAuthId[MAX_AUTHID_LENGTH];
    if (!GetClientAuthId(iClient, AuthId_Steam2, szPlayerAuthId, sizeof(szPlayerAuthId))) {
        strcopy(szPlayerAuthId, sizeof(szPlayerAuthId), "UNKNOWN");
    }

    int iPlayerTeamIndex = GetClientTeam(iClient);
    int iPlayerUserId    = GetClientUserId(iClient);
    int IsLogged = 0;
    for (int i = 0; i < sizeof(g_szWeaponList); i++) {
        if (g_iWeaponStats[iClient][i][LOG_HIT_SHOTS] > 0) {
            LogToGame("\"%N<%d><%s><%s>\" triggered \"weaponstats\" (weapon \"%s\") (shots \"%d\") (hits \"%d\") (kills \"%d\") (headshots \"%d\") (tks \"%d\") (damage \"%d\") (deaths \"%d\")", iClient, iPlayerUserId, szPlayerAuthId, g_szTeamList[iPlayerTeamIndex], g_szWeaponList[i], g_iWeaponStats[iClient][i][LOG_HIT_SHOTS], g_iWeaponStats[iClient][i][LOG_HIT_HITS], g_iWeaponStats[iClient][i][LOG_HIT_KILLS], g_iWeaponStats[iClient][i][LOG_HIT_HEADSHOTS], g_iWeaponStats[iClient][i][LOG_HIT_TEAMKILLS], g_iWeaponStats[iClient][i][LOG_HIT_DAMAGE], g_iWeaponStats[iClient][i][LOG_HIT_DEATHS]);
            LogToGame("\"%N<%d><%s><%s>\" triggered \"weaponstats_hitgroup\" (weapon \"%s\") (head \"%d\") (chest \"%d\") (stomach \"%d\") (leftarm \"%d\") (rightarm \"%d\") (leftleg \"%d\") (rightleg \"%d\")", iClient, iPlayerUserId, szPlayerAuthId, g_szTeamList[iPlayerTeamIndex], g_szWeaponList[i], g_iWeaponStats[iClient][i][LOG_HIT_HEAD], g_iWeaponStats[iClient][i][LOG_HIT_CHEST], g_iWeaponStats[iClient][i][LOG_HIT_STOMACH], g_iWeaponStats[iClient][i][LOG_HIT_LEFTARM], g_iWeaponStats[iClient][i][LOG_HIT_RIGHTARM], g_iWeaponStats[iClient][i][LOG_HIT_LEFTLEG], g_iWeaponStats[iClient][i][LOG_HIT_RIGHTLEG]);
            IsLogged++;
        }
    }
    if (IsLogged > 0) {
        ResetPlayerStats(iClient);
    }
}

void ResetPlayerStats(int iClient)
{
    for (int i = 0; i < sizeof(g_szWeaponList); i++)
    {
        g_iWeaponStats[iClient][i][LOG_HIT_SHOTS]     = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_HITS]      = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_KILLS]     = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_HEADSHOTS] = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_TEAMKILLS] = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_DAMAGE]    = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_DEATHS]    = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_GENERIC]   = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_HEAD]      = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_CHEST]     = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_STOMACH]   = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_LEFTARM]   = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_RIGHTARM]  = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_LEFTLEG]   = 0;
        g_iWeaponStats[iClient][i][LOG_HIT_RIGHTLEG]  = 0;
    }
}

stock int GetWeaponIndex(const char[] szWeaponName) {
    int iIdx = -1;
    g_smWeaponTrie.GetValue(szWeaponName, iIdx);
    return iIdx;
}

void WstatsDumpAll() {
    for (int i = 1; i <= MaxClients; i++) {
        DumpPlayerStats(i);
    }
}

public void OnClientPutInServer(int iClient) {
    ResetPlayerStats(iClient);
}

Action FlushWeaponLogs(Handle hTimer) {
    WstatsDumpAll();
    return Plugin_Continue;
}

void Event_PlayerShoot(Event eEvent, const char[] szName, bool bDontBroadcast) {
    // "local"         "1"             // don't network this, its way too spammy
    // "userid"        "short"
    // "weapon"        "string"        // used weapon name
    // "weaponid"      "short"         // used weapon ID
    // "count"         "short"         // number of bullets
    int iAttacker = GetClientOfUserId(eEvent.GetInt("userid"));
    if (iAttacker > 0) {
        char szWeapon[MAX_WEAPON_LEN];
        eEvent.GetString("weapon", szWeapon, sizeof(szWeapon));
        int iWeaponIndex = GetWeaponIndex(szWeapon);
        if (iWeaponIndex > -1) g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_SHOTS]++;
    }
}

void Event_PlayerHurt(Event eEvent, const char[] szName, bool bDontBroadcast) {
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
    int iAttacker  = GetClientOfUserId(eEvent.GetInt("attacker"));

    if (iAttacker <= 0) {
        return;
    }

    char szWeapon[MAX_WEAPON_LEN];
    GetEventString(eEvent, "weapon", szWeapon, sizeof(szWeapon));

    int iWeaponIndex = GetWeaponIndex(szWeapon);
    if (iWeaponIndex > -1)
    {
        g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_HITS]++;
        g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_DAMAGE] += eEvent.GetInt("dmg_health");
        int iHitGroup  = eEvent.GetInt("hitgroup");
        if (iHitGroup < 8) {
            g_iWeaponStats[iAttacker][iWeaponIndex][iHitGroup + LOG_HIT_OFFSET]++;
        }
    }
    
    else if (!strcmp(szWeapon, "insect_swarm"))
    {
        int iVictim = GetClientOfUserId(eEvent.GetInt("userid"));

        if (iVictim > 0 && IsClientInGame(iVictim) && GetClientTeam(iVictim) == TEAM_SURVIVOR && !IsClientIncapacitated(iVictim))
            LogPlayerToPlayerEvent(iAttacker, iVictim, "triggered", "spit_hurt", true);
    }
}

// "local"         "1"             // don't network this, its way too spammy
// "attacker"      "short"         // player userid who attacked
// "entityid"      "long"          // entity id of infected
// "hitgroup"      "byte"          // hitgroup that was damaged
// "amount"        "short"         // how much damage was done
// "type"          "long"          // damage type
void Event_InfectedHurt(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iAttacker  = GetClientOfUserId(eEvent.GetInt("attacker"));
    if (iAttacker > 0 && IsClientInGame(iAttacker))
    {
        char szWeapon[MAX_WEAPON_LEN];
        GetClientWeapon(iAttacker, szWeapon, sizeof(szWeapon));

        int iWeaponIndex = GetWeaponIndex(szWeapon[7]);
        if (iWeaponIndex > -1)
        {
            g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_HITS]++;
            g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_DAMAGE] += eEvent.GetInt("amount");
            int iHitGroup  = eEvent.GetInt("hitgroup");

            if (iHitGroup < 8) {
                g_iWeaponStats[iAttacker][iWeaponIndex][iHitGroup + LOG_HIT_OFFSET]++;
            }
        }
    }
}

void Event_PlayerDeathPre(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iAttacker = GetClientOfUserId(eEvent.GetInt("attacker"));

    if (eEvent.GetBool("headshot")) {
        LogPlayerEvent(iAttacker, "triggered", "headshot");
    }

    if (g_bIsL4D2 && iAttacker > 0 && IsClientInGame(iAttacker))
    {
        char szWeapon[32];
        eEvent.GetString("weapon", szWeapon, sizeof(szWeapon));
        if (strncmp(szWeapon, "melee", 5) == 0)
        {
            int iWeapon = GetEntDataEnt2(iAttacker, g_iActiveWeaponOffset);
            if (IsValidEdict(iWeapon))
            {
                // They have time to switch weapons after the kill before the death event
                GetEdictClassname(iWeapon, szWeapon, sizeof(szWeapon));
                if (strncmp(szWeapon[7], "melee", 5) == 0) {
                    GetEntPropString(iWeapon, Prop_Data, "m_strMapSetScriptName", szWeapon, sizeof(szWeapon));
                    eEvent.SetString("weapon", szWeapon);
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
void Event_PlayerDeath(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iVictim   = GetClientOfUserId(eEvent.GetInt("userid"));
    int iAttacker = GetClientOfUserId(eEvent.GetInt("attacker"));

    if (iVictim > 0 && iAttacker > 0 && IsClientInGame(iAttacker) && IsClientInGame(iVictim)) {
        char szWeapon[MAX_WEAPON_LEN];
        eEvent.GetString("weapon", szWeapon, sizeof(szWeapon));
        int iWeaponIndex = GetWeaponIndex(szWeapon);
        if (iWeaponIndex > -1) {
            g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_KILLS]++;
            if (eEvent.GetBool("headshot")) {
                g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_HEADSHOTS]++;
            }
            g_iWeaponStats[iVictim][iWeaponIndex][LOG_HIT_DEATHS]++;
            if (GetClientTeam(iAttacker) == GetClientTeam(iVictim)) {
                g_iWeaponStats[iAttacker][iWeaponIndex][LOG_HIT_TEAMKILLS]++;
            }
            DumpPlayerStats(iVictim);
        }
    }
}

void Event_RoundEnd(Event eEvent, const char[] szName, bool bDontBroadcast) {
    WstatsDumpAll();
}

void Event_PlayerSpawn(Event eEvent, const char[] szName, bool bDontBroadcast) {
    // "userid"        "short"         // user ID on server
    int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
    if (iClient > 0) ResetPlayerStats(iClient);
}

void Event_PlayerDisconnect(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(eEvent.GetInt("userid"));

    if (iClient > 0 && IsClientInGame(iClient)) {
        DumpPlayerStats(iClient);
        ResetPlayerStats(iClient);
    }
}

Action Timer_LogMap(Handle timer)
{
    // Called 1 second after OnPluginStart since srcds does not log the first map loaded. Idea from Stormtrooper's "mapfix.sp" for psychostats
    char szMap[64];
    GetCurrentMap(szMap, sizeof(szMap));
    LogToGame("Loading map \"%s\"", szMap);

    return Plugin_Continue;
}

void Event_RescueSurvivor(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("rescuer"));
    if (iPlayer > 0) LogPlayerEvent(iPlayer, "triggered", "rescued_survivor", true);
}

void Event_Heal(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("userid"));
    if (iPlayer <= 0) return;
    if (iPlayer == GetClientOfUserId(eEvent.GetInt("subject"))) return;
    LogPlayerEvent(iPlayer, "triggered", "healed_teammate", true);
}

void Event_Revive(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("userid"));
    if (iPlayer > 0) LogPlayerEvent(iPlayer, "triggered", "revived_teammate", true);
}

void Event_StartleWitch(Event eEvent, const char[] szName, bool bDontBroadcast) {
    int iPlayer = GetClientOfUserId(eEvent.GetInt("userid"));
    if (iPlayer > 0 && eEvent.GetBool("first")) LogPlayerEvent(iPlayer, "triggered", "startled_witch", true);
}

void Event_Pounce(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("userid"));
    int iVictim = GetClientOfUserId(eEvent.GetInt("victim"));
    if (iVictim > 0) LogPlayerToPlayerEvent(iPlayer, iVictim, "triggered", "pounce", true);
    else             LogPlayerEvent(iPlayer, "triggered", "pounce", true);
}

void Event_Boomered(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("attacker"));
    int iVictim = GetClientOfUserId(eEvent.GetInt("userid"));
    if (iPlayer > 0 && eEvent.GetBool("by_boomer")) {
        if (iVictim > 0) LogPlayerToPlayerEvent(iPlayer, iVictim, "triggered", "vomit", true);
        else             LogPlayerEvent(iPlayer, "triggered", "vomit", true);
    }
}

void Event_FF(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("attacker"));
    int iVictim = GetClientOfUserId(eEvent.GetInt("victim"));
    if (iPlayer > 0 && iPlayer == GetClientOfUserId(eEvent.GetInt("guilty"))) {
        if (iVictim > 0) LogPlayerToPlayerEvent(iPlayer, iVictim, "triggered", "friendly_fire", true);
        else             LogPlayerEvent(iPlayer, "triggered", "friendly_fire", true);
    }
}

void Event_WitchKilled(Event eEvent, const char[] szName, bool bDontBroadcast) {
    if (eEvent.GetBool("oneshot")) LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "cr0wned", true);
}

void Event_Defib(Event eEvent, const char[] szName, bool bDontBroadcast) {
    LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "defibrillated_teammate", true);
}

void Event_Adrenaline(Event eEvent, const char[] szName, bool bDontBroadcast) {
    LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "used_adrenaline", true);
}

void Event_JockeyRide(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("userid"));
    int iVictim = GetClientOfUserId(eEvent.GetInt("victim"));

    if (iPlayer > 0) {
        if (iVictim > 0) LogPlayerToPlayerEvent(iPlayer, iVictim, "triggered", "jockey_ride", true);
        else             LogPlayerEvent(iPlayer, "triggered", "jockey_ride", true);
    }
}

void Event_ChargerPummelStart(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    int iPlayer = GetClientOfUserId(eEvent.GetInt("userid"));
    int iVictim = GetClientOfUserId(eEvent.GetInt("victim"));

    if (iVictim > 0) LogPlayerToPlayerEvent(iPlayer, iVictim, "triggered", "charger_pummel", true);
    else             LogPlayerEvent(iPlayer, "triggered", "charger_pummel", true);
}

void Event_VomitBombTank(Event eEvent, const char[] szName, bool bDontBroadcast) {
    LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "bilebomb_tank", true);
}

void Event_ScavengeEnd(Event eEvent, const char[] szName, bool bDontBroadcast) {
    LogTeamEvent(GetEventInt(eEvent, "winners"), "triggered", "Scavenge_Win");
}

void Event_VersusEnd(Event eEvent, const char[] szName, bool bDontBroadcast) {
    LogTeamEvent(GetEventInt(eEvent, "winners"), "triggered", "Versus_Win");
}

// "userid"         "short"         // player who earned the award
// "entityid"       "long"          // client likes ent id
// "subjectentid"   "long"          // entity id of other party in the award, if any
// "award"          "short"         // id of award earned
void Event_Award(Event eEvent, const char[] szName, bool bDontBroadcast)
{
    switch (GetEventInt(eEvent, "award"))
    {
        case AWARD_HUNTER_PUNTER:
            LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "hunter_punter", true);

        case AWARD_TONGUE_TWISTER:
            LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "tounge_twister", true);

        case AWARD_PROTECT_TEAMMATE:
            LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "protect_teammate", true);

        case AWARD_NO_DEATH_ON_TANK:
            LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "no_death_on_tank", true);

        case AWARD_KILLED_ALL_SURVIVORS:
            LogPlayerEvent(GetClientOfUserId(eEvent.GetInt("userid")), "triggered", "killed_all_survivors", true);
    }
}

void LogPlayerEvent(int iClient, const char[] szVerb, const char[] szEvent, bool bDisplayLocation = false)
{
    if (IsValidPlayer(iClient))
    {
        char szPlayerAuthId[MAX_AUTHID_LENGTH];
        GetClientAuthIdSafe(iClient, szPlayerAuthId, sizeof(szPlayerAuthId));

        if (bDisplayLocation)
        {
            float vPlayerOrigin[3];
            GetClientAbsOrigin(iClient, vPlayerOrigin);
            LogToGame("\"%N<%d><%s><%s><setpos_exact %.2f %.2f %.2f>\" %s \"%s\"", iClient, GetClientUserId(iClient), szPlayerAuthId, g_szTeamList[GetClientTeam(iClient)], vPlayerOrigin[0], vPlayerOrigin[1], vPlayerOrigin[2], szVerb, szEvent);
        } else {
            LogToGame("\"%N<%d><%s><%s>\" %s \"%s\"", iClient, GetClientUserId(iClient), szPlayerAuthId, g_szTeamList[GetClientTeam(iClient)], szVerb, szEvent);
        }
    }
}

void LogPlayerToPlayerEvent(int iClient, int iVictim, const char[] szVerb, const char[] szEvent, bool bDisplayLocation = false)
{
    if (IsValidPlayer(iClient) && IsValidPlayer(iVictim))
    {
        char szPlayerAuthId[MAX_AUTHID_LENGTH];
        GetClientAuthIdSafe(iClient, szPlayerAuthId, sizeof(szPlayerAuthId));

        char szVictimAuthId[MAX_AUTHID_LENGTH];
        GetClientAuthIdSafe(iVictim, szVictimAuthId, sizeof(szVictimAuthId));
        
        if (bDisplayLocation) {
            float vPlayerOrigin[3];
            GetClientAbsOrigin(iClient, vPlayerOrigin);
            float vVictimOrigin[3];
            GetClientAbsOrigin(iVictim, vVictimOrigin);
            LogToGame("\"%N<%d><%s><%s><setpos_exact %.2f %.2f %.2f>\" %s \"%s\" against \"%N<%d><%s><%s><setpos_exact %.2f %.2f %.2f>\"", iClient, GetClientUserId(iClient), szPlayerAuthId, g_szTeamList[GetClientTeam(iClient)], vPlayerOrigin[0], vPlayerOrigin[1], vPlayerOrigin[2], szVerb, szEvent, iVictim, GetClientUserId(iVictim), szVictimAuthId, g_szTeamList[GetClientTeam(iVictim)], vVictimOrigin[0], vVictimOrigin[1], vVictimOrigin[2]);
        } else {
            LogToGame("\"%N<%d><%s><%s>\" %s \"%s\" against \"%N<%d><%s><%s>\"", iClient, GetClientUserId(iClient), szPlayerAuthId, g_szTeamList[GetClientTeam(iClient)], szVerb, szEvent, iVictim, GetClientUserId(iVictim), szVictimAuthId, g_szTeamList[GetClientTeam(iVictim)]);
        }
    }
}

void LogKill(int iAttacker, int iVictim, const char[] szWeapon, bool bDisplayLocation = false)
{
    if (IsValidPlayer(iAttacker) && IsValidPlayer(iVictim))
    {
        char szAttackerAuthId[MAX_AUTHID_LENGTH];
        GetClientAuthIdSafe(iAttacker, szAttackerAuthId, sizeof(szAttackerAuthId));

        char szVictimAuthId[MAX_AUTHID_LENGTH];
        GetClientAuthIdSafe(iVictim, szVictimAuthId, sizeof(szVictimAuthId));

        if (bDisplayLocation) {
            float vAttackerOrigin[3];
            GetClientAbsOrigin(iAttacker, vAttackerOrigin);
            float vVictimOrigin[3];
            GetClientAbsOrigin(iVictim, vVictimOrigin);
            LogToGame("\"%N<%d><%s><%s><setpos_exact %.2f %.2f %.2f>\" killed \"%N<%d><%s><%s><setpos_exact %.2f %.2f %.2f>\" with \"%s\"", iAttacker, GetClientUserId(iAttacker), szAttackerAuthId, g_szTeamList[GetClientTeam(iAttacker)], vAttackerOrigin[0], vAttackerOrigin[1], vAttackerOrigin[2], iVictim, GetClientUserId(iVictim), szVictimAuthId, g_szTeamList[GetClientTeam(iVictim)], vVictimOrigin[0], vVictimOrigin[1], vVictimOrigin[2], szWeapon);
        } else {
            LogToGame("\"%N<%d><%s><%s>\" killed \"%N<%d><%s><%s>\" with \"%s\"", iAttacker, GetClientUserId(iAttacker), szAttackerAuthId, g_szTeamList[GetClientTeam(iAttacker)], iVictim, GetClientUserId(iVictim), szVictimAuthId, g_szTeamList[GetClientTeam(iVictim)], szWeapon);
        }
    }
}

void LogSuicide(int iVictim, const char[] szWeapon, bool bDisplayLocation = false)
{
    if (IsValidPlayer(iVictim))
    {
        char szVictimAuthId[MAX_AUTHID_LENGTH];
        GetClientAuthIdSafe(iVictim, szVictimAuthId, sizeof(szVictimAuthId));

        if (bDisplayLocation) {
            float vVictimOrigin[3];
            GetClientAbsOrigin(iVictim, vVictimOrigin);
            LogToGame("\"%N<%d><%s><%s>\" committed suicide with \"%s\" (victim_position \"%d %d %d\")", iVictim, GetClientUserId(iVictim), szVictimAuthId, g_szTeamList[GetClientTeam(iVictim)], szWeapon, RoundFloat(vVictimOrigin[0]), RoundFloat(vVictimOrigin[1]), RoundFloat(vVictimOrigin[2]));
        } else {
            LogToGame("\"%N<%d><%s><%s>\" committed suicide with \"%s\"", iVictim, GetClientUserId(iVictim), szVictimAuthId, g_szTeamList[GetClientTeam(iVictim)], szWeapon);
        }
    }
}

// Verb should always be "triggered" for this.
void LogTeamEvent(int iTeam, const char[] szVerb, const char[] szEvent)
{
    if (iTeam >= 0) {
        LogToGame("Team \"%s\" %s \"%s\"", g_szTeamList[iTeam], szVerb, szEvent);
    }
}

void LogKillLoc(int iAttacker, int iVictim)
{
    if (iAttacker > 0 && iVictim > 0)
    {
        float vAttackerOrigin[3];
        GetClientAbsOrigin(iAttacker, vAttackerOrigin);
        float vVictimOrigin[3];
        GetClientAbsOrigin(iVictim, vVictimOrigin);
        LogToGame("World triggered \"killlocation\" (attacker_position \"%d %d %d\") (victim_position \"%d %d %d\")", RoundFloat(vAttackerOrigin[0]), RoundFloat(vAttackerOrigin[1]), RoundFloat(vAttackerOrigin[2]), RoundFloat(vVictimOrigin[0]), RoundFloat(vVictimOrigin[1]), RoundFloat(vVictimOrigin[2]));
    }
}

void LogTeamChange(int iClient, int iNewTeam)
{
    if (IsValidPlayer(iClient))
    {
        char szPlayerAuthId[MAX_AUTHID_LENGTH];
        GetClientAuthIdSafe(iClient, szPlayerAuthId, sizeof(szPlayerAuthId));

        LogToGame("\"%N<%d><%s><%s>\" joined team \"%s\"%s", iClient, GetClientUserId(iClient), szPlayerAuthId, g_szTeamList[GetClientTeam(iClient)], g_szTeamList[iNewTeam]);
    }
}

void LogRoleChange(int iClient, const char[] szRole)
{
    if (IsValidPlayer(iClient)) {
        char szPlayerAuthId[MAX_AUTHID_LENGTH];
        if (!GetClientAuthId(iClient, AuthId_Engine, szPlayerAuthId, sizeof(szPlayerAuthId), false)) {
            strcopy(szPlayerAuthId, sizeof(szPlayerAuthId), "UNKNOWN");
        }
        LogToGame("\"%N<%d><%s><%s>\" changed role to \"%s\"", iClient, GetClientUserId(iClient), szPlayerAuthId, g_szTeamList[GetClientTeam(iClient)], szRole);
    }
}


void GetClientAuthIdSafe(int client, char[] buffer, int maxlen)
{
    if (!GetClientAuthId(client, AuthId_Engine, buffer, maxlen, false))
    {
        strcopy(buffer, maxlen, "UNKNOWN");
    }
}

void CacheTeams()
{
    for (int i = 0; i < 4; i++)
    {
        GetTeamName(i, g_szTeamList[i], sizeof(g_szTeamList[]));
    }
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