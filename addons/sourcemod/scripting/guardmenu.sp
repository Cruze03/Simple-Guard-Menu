/*
 * SourceMod Entity Projects
 * by: Entity
 *
 * Copyright (C) 2020 Kőrösfalvi "Entity" Martin
 *
 * This program is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 3 of the License, or (at your option) 
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 */
#include <sourcemod>
#include <cstrike>
#include <clientprefs>
#include <sdktools>
#include <sdkhooks>
#include <scp>
#include <sourcecomms>

#pragma newdecls required

//Global
#define MAX_BUTTONS 25

Handle RoundTimeTicker;
Handle TickerState = INVALID_HANDLE;
bool g_bEnabled = true;
bool g_bMutePrisoners = true;
bool g_bExtendTime = true;
bool g_bTagging = true;

bool g_bTeamBlock = true;
bool g_bFriendlyFire = true;
bool g_bExtend = true;
bool g_bTMute = true;
int g_RoundTime;
bool g_bIsClientCT[MAXPLAYERS + 1];

//Translations
char Prefix[32] = "\x01[\x0CGuardMenu\x01] \x0B";
char t_Name[16] = "\x06GuardMenu\x0B";
char t_cmd_o[16] = "\x06!gm\x0B";
char t_cmd_t[16] = "\x06!guardmenu\x0B";
char t_Team[16] = "\x06CT\x0B"; 

//ConVars
ConVar g_hEnabled;
ConVar g_hMutePrisoners;
ConVar g_hExtendTime;
ConVar g_hTagging;
ConVar g_hDefaultBlock;
ConVar g_hDefaultFF;


ConVar g_hTeamBlock;
ConVar g_hFriendlyFire;
ConVar g_hRoundTime;

public Plugin myinfo = 
{
	name = "[CSGO] JailBreak Guard Menu", 
	author = "Entity", 
	description = "Simple Round Control menu for guards", 
	version = "1.2"
};

public void OnPluginStart()
{
	LoadTranslations("guardmenu.phrases");

	g_hEnabled = CreateConVar("sm_gm_enabled", "1", "Enable the guardmenu system?", 0, true, 0.0, true, 1.0);
	g_hMutePrisoners = CreateConVar("sm_gm_mute", "1", "Enable prisoner mute part?", 0, true, 0.0, true, 1.0);
	g_hExtendTime = CreateConVar("sm_gm_extend", "1", "Enable time extend part?", 0, true, 0.0, true, 1.0);
	g_hTagging = CreateConVar("sm_gm_tagging", "1", "Enable player tagging part?", 0, true, 0.0, true, 1.0);
	g_hDefaultBlock = CreateConVar("sm_gm_defaultblock", "1", "The default state of TeamBlock", 0, true, 0.0, true, 1.0);
	g_hDefaultFF = CreateConVar("sm_gm_defaultff", "0", "The default state of FriendlyFire", 0, true, 0.0, true, 1.0);
	
	HookConVarChange(g_hEnabled, OnCvarChange_Enabled);
	HookConVarChange(g_hMutePrisoners, OnCvarChange_Mute);
	HookConVarChange(g_hExtendTime, OnCvarChange_Extend);
	HookConVarChange(g_hTagging, OnCvarChange_Tagging);
	
	RegConsoleCmd("sm_guardmenu", Command_GuardMenu);
	RegConsoleCmd("sm_gm", Command_GuardMenu);
	
	HookEvent("player_spawn", OnPlayerSpawn);
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_end", OnRoundEnd);
	HookEvent("server_cvar", OnServerCvar, EventHookMode_Pre);
	
	g_hTeamBlock = FindConVar("mp_solid_teammates");
	g_hFriendlyFire = FindConVar("mp_friendlyfire");
	g_hRoundTime = FindConVar("mp_roundtime");
	
	AutoExecConfig(true, "guardmenu");
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if ((IsClientInGame(i)) && (IsPlayerAlive(i)))
		{
			int IsClientCT = GetClientTeam(i);
			SDKHook(i, SDKHook_OnTakeDamage, BlockDamageForCT);
			if (IsClientCT == 3)
			{
				g_bIsClientCT[i] = true;
				PrintToChat(i, "%s %t", Prefix, "StartMessage", t_Name, t_cmd_o, t_cmd_t);
			}
			else
			{
				g_bIsClientCT[i] = false;
			}
		}
	}
}

public void OnCvarChange_Enabled(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if (StrEqual(newvalue, "1")) g_bEnabled = true;
	else if (StrEqual(newvalue, "0")) g_bEnabled = false;
}

public void OnCvarChange_Mute(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if (StrEqual(newvalue, "1"))
	{
		g_bMutePrisoners = true;
		g_bTMute = true;
	}
	else if (StrEqual(newvalue, "0"))
	{
		g_bMutePrisoners = false;
		g_bTMute = false;
	}
}

public void OnCvarChange_Extend(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if (StrEqual(newvalue, "1"))
	{
		g_bExtendTime = true;
		g_bExtend = true;
	}
	else if (StrEqual(newvalue, "0"))
	{
		g_bExtendTime = false;
		g_bExtend = false;
	}
}

public void OnCvarChange_Tagging(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if (StrEqual(newvalue, "1")) g_bTagging = true;
	else if (StrEqual(newvalue, "0")) g_bTagging = false;
}

public Action Timer_RoundTimeLeft(Handle timer, int RoundTime)
{
	if (g_RoundTime == 5)
	{
		return Plugin_Stop;
	}
	else
	{
		if (g_RoundTime != 0)
		{
			g_RoundTime = g_RoundTime - 1;
		}
	}
	return Plugin_Continue;
}

public Action OnServerCvar(Handle event, const char[] name, bool dontBroadcast)
{
	char sConVarName[64];
	sConVarName[0] = '\0';
	GetEventString(event, "cvarname", sConVarName, sizeof(sConVarName));
	if (StrContains(sConVarName, "mp_friendlyfire", false) >= 0 || StrContains(sConVarName, "mp_solid_teammates", false) >= 0 || StrContains(sConVarName, "sv_alltalk", false) >= 0 || StrContains(sConVarName, "sv_full_alltalk", false) >= 0 || StrContains(sConVarName, "sv_deadtalk", false) >= 0)
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}  

public Action Command_GuardMenu(int client, int args)
{
	if (!g_bEnabled)
	{
		PrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
		return;
	}
	
	if (g_bIsClientCT[client] == true)
	{
		if (IsPlayerAlive(client))
		{
			if (IsClientInGame(client))
			{
				ShowGuardMenu(client, 0);
			}
			else
			{
				PrintToChat(client, "%s %t", Prefix, "MustBeInGame");
			}
		}
		else
		{
			PrintToChat(client, "%s %t", Prefix, "TurnedOff");
		}
	}
	else
	{
		PrintToChat(client, "%s %t", Prefix, "OnlyGuards", t_Name, t_Team);
	}
}

stock void ShowGuardMenu(int client, int itemNum)
{
	Menu menu = CreateMenu(GuardMenuChoice);
	menu.SetTitle("GuardMenu - By Entity");
	char sTB[64], t_Extend[64], t_MuteT[64], t_TagP[64], t_UnTagP[64];
	Format(t_Extend, sizeof(t_Extend), "%t", "RoundExtend");
	Format(t_MuteT, sizeof(t_MuteT), "%t", "MutePrisoners");
	Format(t_TagP, sizeof(t_TagP), "%t", "TagPlayer");
	Format(t_UnTagP, sizeof(t_UnTagP), "%t", "UnTagPlayer");
	if (GetConVarInt(g_hTeamBlock) == 1)
	{
		Format(sTB, sizeof(sTB), "%t", "TeamBlockOff");
		menu.AddItem("teamblock", sTB, g_bTeamBlock ? 0 : 1);
	}
	else
	{
		Format(sTB, sizeof(sTB), "%t", "TeamBlockOn");
		menu.AddItem("teamblock", sTB, g_bTeamBlock ? 0 : 1);
	}
	char sFF[64];
	if (GetConVarInt(g_hFriendlyFire) == 0)
	{
		Format(sFF, sizeof(sFF), "%t", "FriendlyFireOn");
		menu.AddItem("friendlyfire", sFF, g_bFriendlyFire ? 0 : 1);
	}
	else
	{
		Format(sFF, sizeof(sFF), "%t", "FriendlyFireOff");
		menu.AddItem("friendlyfire", sFF, g_bFriendlyFire ? 0 : 1);
	}
	menu.AddItem("extend", t_Extend, g_bExtend ? 0 : 1);
	menu.AddItem("mutet", t_MuteT, g_bTMute ? 0 : 1);
	menu.AddItem("tagfd", t_TagP, g_bTagging ? 0 : 1);
	menu.AddItem("untagfd", t_UnTagP, g_bTagging ? 0 : 1);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int GuardMenuChoice(Menu menu, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			PrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
			return;
		}
		
		char info[64];
		GetMenuItem(menu, itemNum, info, sizeof(info));
		if (StrEqual(info, "teamblock"))
		{
			if (GetConVarInt(g_hTeamBlock) == 1)
			{
				SetConVarInt(g_hTeamBlock, 0, true, false);
				ShowGuardMenu(client, itemNum);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "TeamBlockTurnedOff");
			}
			else
			{
				SetConVarInt(g_hTeamBlock, 1, true, false);
				ShowGuardMenu(client, itemNum);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "TeamBlockTurnedOn");
			}
		}
		if (StrEqual(info, "friendlyfire"))
		{
			if (GetConVarInt(g_hFriendlyFire) == 1)
			{
				SetConVarInt(g_hFriendlyFire, 0, true, false);
				ShowGuardMenu(client, itemNum);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "FriendlyFireTurnedOff");
			}
			else
			{
				SetConVarInt(g_hFriendlyFire, 1, true, false);
				ShowGuardMenu(client, itemNum);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "FriendlyFireTurnedOn");
			}
		}
		if (StrEqual(info, "extend"))
		{
			if (g_RoundTime > 5)
			{
				g_bExtend = false;				
				GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0)+300, 4, 0, true);
				g_RoundTime = g_RoundTime + 300;
				ShowGuardMenu(client, itemNum);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "RoundExtended");
			}
			else
			{
				PrintToChat(client, "%s %t", Prefix, "ExtendDenied");
			}
		}
		if (StrEqual(info, "mutet"))
		{
			if (g_RoundTime > 60)
			{
				g_bTMute = false;
				for(int i = 1; i <= MaxClients; i++)
				{
					if ( (IsClientInGame(i)) && (IsPlayerAlive(i)))
					{
						if (GetClientTeam(i) == CS_TEAM_T)
						{
							SourceComms_SetClientMute(i, true, 1, true, "GuardMenu");
						}
					}
				}
				ShowGuardMenu(client, itemNum);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "PrisonersMuted");
			}
			else
			{
				PrintToChat(client, "%s %t", Prefix, "MuteDeined");
			}
		}
		if (StrEqual(info, "tagfd"))
		{
			int TargetID = GetClientAimTarget(client, true);
			Command_TagPlayer(client, TargetID);
			ShowGuardMenu(client, itemNum);
			PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "Tagged", TargetID);
		}
		if (StrEqual(info, "untagfd"))
		{
			int TargetID = GetClientAimTarget(client, true);
			Command_UnTagPlayer(client, TargetID);
			ShowGuardMenu(client, itemNum);
			PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "UnTagged", TargetID);
		}
	}
}

public Action Command_TagPlayer(int client, int target)
{
	if ((IsClientInGame(client)) && (IsPlayerAlive(client)))
	{
		SetEntityRenderColor(target, 0, 255, 0, 75);
	}
	else
	{
		PrintToChat(client, "%s %t", Prefix, "TargetNotFound");
	}
}

public Action Command_UnTagPlayer(int client, int target)
{
	if (!(client == target))
	{
		SetEntityRenderColor(target, 255, 255, 255, 255);
	}
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	int IsClientCT = GetClientTeam(client);
	if (IsClientCT == 3)
	{
		g_bIsClientCT[client] = true;
		PrintToChat(client, "%s %t", Prefix, "StartMessage", t_Name, t_cmd_o, t_cmd_t);
	}
	else
	{
		g_bIsClientCT[client] = false;
	}

	SDKHook(client, SDKHook_OnTakeDamage, BlockDamageForCT);
}


public Action BlockDamageForCT(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
	if ((IsClientInGame(victim) && (victim > 0 && victim <= MAXPLAYERS)) &&
		IsClientInGame(attacker) && (attacker > 0 && attacker <= MAXPLAYERS))
	{
		int VictimTeam = GetClientTeam(victim);
		int AttackerTeam = GetClientTeam(attacker);
		if ((GetConVarInt(g_hFriendlyFire) == 1) && (VictimTeam == 3) && (AttackerTeam == 3))
		{
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action OnRoundStart(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	SDKHook(client, SDKHook_OnTakeDamage, BlockDamageForCT);

	if (g_bMutePrisoners == false) g_bTMute = false;
	if (g_bExtendTime == false) g_bExtend = false;
	g_RoundTime = GetConVarInt(g_hRoundTime) * 60;
	if (TickerState == INVALID_HANDLE)
	{
		RoundTimeTicker = CreateTimer(1.0, Timer_RoundTimeLeft, g_RoundTime, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		KillTimer(RoundTimeTicker);
		RoundTimeTicker = CreateTimer(1.0, Timer_RoundTimeLeft, g_RoundTime, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action OnRoundEnd(Event event, char[] name, bool dontBroadcast)
{
	if (TickerState != INVALID_HANDLE)
	{
		KillTimer(RoundTimeTicker);
	}
	if (g_bMutePrisoners == true) g_bTMute = true;
	if (g_bExtendTime == true) g_bExtend = true;
	
	if (GetConVarInt(g_hDefaultBlock) == 1)
	{
		SetConVarInt(g_hTeamBlock, 1, true, false);
	}
	else
	{
		SetConVarInt(g_hTeamBlock, 0, true, false);
	}
	
	if (GetConVarInt(g_hDefaultFF) == 1)
	{
		SetConVarInt(g_hFriendlyFire, 1, true, false);
	}
	else
	{
		SetConVarInt(g_hFriendlyFire, 0, true, false);
	}
	
	if (g_bTagging == true)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if ( (IsClientInGame(i)) && (IsPlayerAlive(i)))
			{
				Command_UnTagPlayer(i, i);
			}
		}
	}
}