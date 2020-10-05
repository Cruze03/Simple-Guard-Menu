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
#undef REQUIRE_PLUGIN
#include <sourcecomms>

#pragma semicolon 1
#pragma newdecls required

//Global
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
bool g_bLate;
bool g_bSourcomms;

//Translations
char Prefix[32] = "\x01[\x0CGuardMenu\x01] \x0B";
char t_Name[16] = "\x06GuardMenu\x0B";
char t_cmd_o[16] = "\x06!gm\x0B";
char t_cmd_t[16] = "\x06!guardmenu\x0B";
char t_Team[16] = "\x06CT\x0B"; 

//ConVars
ConVar g_hEnabled;
ConVar g_hMutePrisoners;
ConVar g_hMutePrisonersDuration;
ConVar g_hExtendTime;
ConVar g_hTagging;
ConVar g_hDefaultBlock;
ConVar g_hDefaultFF;

ConVar g_hTeamBlock;
ConVar g_hFriendlyFire;
ConVar g_hTeammatesAreEnemies;
ConVar g_hRoundTime;

public Plugin myinfo = 
{
	name = "[CSGO] JailBreak Guard Menu", 
	author = "Entity", 
	description = "Simple Round Control menu for guards", 
	version = "1.3",
	url = "https://github.com/Sples1/Simple-Guard-Menu/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	MarkNativeAsOptional("SourceComms_SetClientMute");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_hEnabled = CreateConVar("sm_gm_enabled", "1", "Enable the guardmenu system?", 0, true, 0.0, true, 1.0);
	g_hMutePrisoners = CreateConVar("sm_gm_mute", "1", "Enable prisoner mute part?", 0, true, 0.0, true, 1.0);
	g_hMutePrisonersDuration = CreateConVar("sm_gm_mute_duration", "1", "Duration to mute prisoners for? In minutes.");
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
	g_hTeammatesAreEnemies = FindConVar("mp_teammates_are_enemies");
	g_hRoundTime = FindConVar("mp_roundtime");

	AutoExecConfig(true, "guardmenu");
	LoadTranslations("guardmenu.phrases");

	if(g_bLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i))
			{
				SDKHook(i, SDKHook_OnTakeDamage, BlockDamageForCT);
				if (GetClientTeam(i) == 3)
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
}

public void OnAllPluginsLoaded()
{
	g_bSourcomms = LibraryExists("sourcecomms");
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "sourcecomms"))
	{
		g_bSourcomms = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "sourcecomms"))
	{
		g_bSourcomms = false;
	}
}

public void OnMapStart()
{
	g_bEnabled = g_hEnabled.BoolValue;
	g_bMutePrisoners = g_hMutePrisoners.BoolValue;
	g_bExtendTime = g_hExtendTime.BoolValue;
	g_bTagging = g_hTagging.BoolValue;
}

public void OnMapEnd()
{
	SetConVarInt(g_hFriendlyFire, 0, true, false);
	SetConVarInt(g_hTeammatesAreEnemies, 0, true, false);
}

public void OnCvarChange_Enabled(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bEnabled = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bEnabled = false;
	}
}

public void OnCvarChange_Mute(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bMutePrisoners = true;
		g_bTMute = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bMutePrisoners = false;
		g_bTMute = false;
	}
}

public void OnCvarChange_Extend(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bExtendTime = true;
		g_bExtend = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bExtendTime = false;
		g_bExtend = false;
	}
}

public void OnCvarChange_Tagging(ConVar cvar, char[] oldvalue, char[] newvalue)
{
	if(StrEqual(newvalue, "1"))
	{
		g_bTagging = true;
	}
	else if(StrEqual(newvalue, "0"))
	{
		g_bTagging = false;
	}
}

public Action Timer_RoundTimeLeft(Handle timer, int RoundTime)
{
	if(g_RoundTime == 5)
	{
		return Plugin_Stop;
	}
	else
	{
		if(g_RoundTime != 0)
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
	if (StrContains(sConVarName, "mp_friendlyfire", false) >= 0 || StrContains(sConVarName, "mp_solid_teammates", false) >= 0 || StrContains(sConVarName, "sv_alltalk", false) >= 0 || StrContains(sConVarName, "sv_full_alltalk", false) >= 0 || StrContains(sConVarName, "sv_deadtalk", false) >= 0 || StrContains(sConVarName, "mp_teammates_are_enemies", false) >= 0)
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

	if(g_bIsClientCT[client])
	{
		if(client)
		{
			if(IsPlayerAlive(client))
			{
				ShowGuardMenu(client);
			}
			else
			{
				PrintToChat(client, "%s %t", Prefix, "TurnedOff");
			}
		}
		else
		{
			PrintToChat(client, "%s %t", Prefix, "MustBeInGame");
		}
	}
	else
	{
		PrintToChat(client, "%s %t", Prefix, "OnlyGuards", t_Name, t_Team);
	}
}

stock void ShowGuardMenu(int client)
{
	char sTB[64], t_Extend[64], t_MuteT[64], t_TagP[64], t_UnTagP[64], sFF[64];
	Format(t_Extend, sizeof(t_Extend), "%t", "RoundExtend");
	Format(t_MuteT, sizeof(t_MuteT), "%t", "MutePrisoners");
	Format(t_TagP, sizeof(t_TagP), "%t", "TagPlayer");
	Format(t_UnTagP, sizeof(t_UnTagP), "%t", "UnTagPlayer");

	Menu menu = new Menu(GuardMenuChoice);
	menu.SetTitle("GuardMenu - By Entity");

	if(GetConVarInt(g_hTeamBlock) == 1)
	{
		Format(sTB, sizeof(sTB), "%t", "TeamBlockOff");
		menu.AddItem("teamblock", sTB, g_bTeamBlock ? 0 : 1);
	}
	else
	{
		Format(sTB, sizeof(sTB), "%t", "TeamBlockOn");
		menu.AddItem("teamblock", sTB, g_bTeamBlock ? 0 : 1);
	}
	if(GetConVarInt(g_hFriendlyFire) == 0)
	{
		Format(sFF, sizeof(sFF), "%t", "FriendlyFireOn");
		menu.AddItem("friendlyfire", sFF, g_bFriendlyFire ? 0 : 1);
	}
	else
	{
		Format(sFF, sizeof(sFF), "%t", "FriendlyFireOff");
		menu.AddItem("friendlyfire", sFF, g_bFriendlyFire ? 0 : 1);
	}
	menu.AddItem("extend", t_Extend, g_bExtendTime&&g_bExtend ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("mutet", t_MuteT, g_bMutePrisoners&&g_bTMute ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("tagfd", t_TagP, g_bTagging ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("untagfd", t_UnTagP, g_bTagging ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int GuardMenuChoice(Menu menu, MenuAction action, int client, int itemNum)
{
	if(action == MenuAction_End)
	{
		delete menu;
	}
	if(action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			PrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
			return;
		}
		
		char info[64];
		GetMenuItem(menu, itemNum, info, sizeof(info));
		if(StrEqual(info, "teamblock"))
		{
			if (GetConVarInt(g_hTeamBlock) == 1)
			{
				SetConVarInt(g_hTeamBlock, 0, true, false);
				ShowGuardMenu(client);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "TeamBlockTurnedOff");
			}
			else
			{
				SetConVarInt(g_hTeamBlock, 1, true, false);
				ShowGuardMenu(client);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "TeamBlockTurnedOn");
			}
		}
		if(StrEqual(info, "friendlyfire"))
		{
			if (GetConVarInt(g_hFriendlyFire) == 1)
			{
				SetConVarInt(g_hFriendlyFire, 0, true, false);
				SetConVarInt(g_hTeammatesAreEnemies, 0, true, false);
				ShowGuardMenu(client);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "FriendlyFireTurnedOff");
			}
			else
			{
				SetConVarInt(g_hFriendlyFire, 1, true, false);
				SetConVarInt(g_hTeammatesAreEnemies, 1, true, false);
				ShowGuardMenu(client);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "FriendlyFireTurnedOn");
			}
		}
		if(StrEqual(info, "extend"))
		{
			if (g_RoundTime > 5)
			{
				g_bExtend = false;				
				GameRules_SetProp("m_iRoundTime", GameRules_GetProp("m_iRoundTime", 4, 0)+300, 4, 0, true);
				g_RoundTime = g_RoundTime + 300;
				ShowGuardMenu(client);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "RoundExtended");
			}
			else
			{
				PrintToChat(client, "%s %t", Prefix, "ExtendDenied");
			}
		}
		if(StrEqual(info, "mutet"))
		{
			if (g_RoundTime > 60)
			{
				g_bTMute = false;
				for(int i = 1; i <= MaxClients; i++)
				{
					if(IsClientInGame(i))
					{
						if(GetClientTeam(i) == CS_TEAM_T)
						{
							if(g_bSourcomms)
							{
								SourceComms_SetClientMute(i, true, g_hMutePrisonersDuration.IntValue, true, "GuardMenu");
							}
							else
							{
								SetClientListeningFlags(i, VOICE_MUTED);
								CreateTimer(g_hMutePrisonersDuration.FloatValue*60, Timer_UnMute, _, TIMER_FLAG_NO_MAPCHANGE);
							}
						}
					}
				}
				ShowGuardMenu(client);
				PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "PrisonersMuted");
			}
			else
			{
				PrintToChat(client, "%s %t", Prefix, "MuteDeined");
			}
		}
		if(StrEqual(info, "tagfd"))
		{
			ShowColorMenu(client);
			PrintToChat(client, "%s \x0B%t", Prefix, "SelectColor");
		}
		if(StrEqual(info, "untagfd"))
		{
			int TargetID = GetClientAimTarget(client, true);
			if(TargetID == -1)
			{
				PrintToChat(client, "%s %t", Prefix, "TargetNotFound");
				ShowGuardMenu(client);
				return;
			}
			Command_UnTagPlayer(client, TargetID);
			ShowGuardMenu(client);
			PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "UnTagged", TargetID);
		}
	}
}

public Action Timer_UnMute(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			if(GetClientTeam(i) == CS_TEAM_T && GetClientListeningFlags(i) == VOICE_MUTED)
			{
				SetClientListeningFlags(i, VOICE_NORMAL);
			}
		}
	}
}

stock void ShowColorMenu(int client)
{
	Menu menu = new Menu(Menu_Handler);
	menu.SetTitle("Tag color");
	menu.AddItem("green", "Green");
	menu.AddItem("blue", "Blue");
	menu.AddItem("pink", "Pink");
	menu.AddItem("yellow", "Yellow");
	menu.AddItem("cyan", "Cyan");
	menu.ExitButton = true;
	menu.ExitBackButton = true;
	menu.Display(client, 30);
}

public int Menu_Handler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_Select)
	{
		if (!g_bEnabled)
		{
			PrintToChat(client, "%s %t", Prefix, "TurnedOff", t_Name);
			return;
		}
		char info[64];
		GetMenuItem(menu, item, info, sizeof(info));
		int TargetID = GetClientAimTarget(client, true);
		if(TargetID == -1)
		{
			PrintToChat(client, "%s %t", Prefix, "TargetNotFound");
			ShowColorMenu(client);
			return;
		}
		if (StrEqual(info, "green"))
		{
			Command_TagPlayer(client, TargetID, 0, 255, 0, "Green");
		}
		if (StrEqual(info, "blue"))
		{
			Command_TagPlayer(client, TargetID, 0, 0, 255, "Blue");
		}
		if (StrEqual(info, "pink"))
		{
			Command_TagPlayer(client, TargetID, 0, 0, 255, "Pink");
		}
		if (StrEqual(info, "yellow"))
		{
			Command_TagPlayer(client, TargetID, 255, 255, 0, "Yellow");
		}
		if (StrEqual(info, "cyan"))
		{
			Command_TagPlayer(client, TargetID, 0, 255, 255, "Cyan");
		}
		ShowGuardMenu(client);
	}
	if (action == MenuAction_Cancel)
	{
		if(item == MenuCancel_ExitBack)
		{
			ShowGuardMenu(client);
		}
	}
	if (action == MenuAction_End)
	{
		delete menu;
	}
}

stock void Command_TagPlayer(int client, int target, int r, int g, int b, char[] color)
{
	if (target != -1 && IsClientInGame(target) && IsPlayerAlive(target))
	{
		SetEntityRenderColor(target, r, g, b, 255);
		ShowGuardMenu(client);
		PrintToChatAll("%s \x06%N\x0B %t", Prefix, client, "Tagged", target, color);
	}
}

stock void Command_UnTagPlayer(int client, int target, bool roundend = false)
{
	if(target != -1 && IsClientInGame(target) && IsPlayerAlive(target))
	{
		SetEntityRenderColor(target, 255, 255, 255, 255);
		if(!roundend)
		{
			ShowGuardMenu(client);
		}
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
	if(victim < 1 || victim > MaxClients || attacker < 1 || attacker > MaxClients)
	{
		return Plugin_Continue;
	}
	
	int VictimTeam = GetClientTeam(victim);
	int AttackerTeam = GetClientTeam(attacker);

	if ((GetConVarInt(g_hFriendlyFire) == 1) && (VictimTeam == 3) && (AttackerTeam == 3))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action OnRoundStart(Event event, char[] name, bool dontBroadcast)
{
	if(!g_bMutePrisoners)
	{
		g_bTMute = false;
	}
	if(!g_bExtendTime)
	{
		g_bExtend = false;
	}
	g_RoundTime = GetConVarInt(g_hRoundTime) * 60;
	if(TickerState == INVALID_HANDLE)
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
	if(TickerState != INVALID_HANDLE)
	{
		KillTimer(RoundTimeTicker);
	}

	if(g_bMutePrisoners)
	{
		g_bTMute = true;
	}

	if(g_bExtendTime)
	{
		g_bExtend = true;
	}

	if(GetConVarInt(g_hDefaultBlock) == 1)
	{
		SetConVarInt(g_hTeamBlock, 1, true, false);
	}
	else
	{
		SetConVarInt(g_hTeamBlock, 0, true, false);
	}
	
	if(GetConVarInt(g_hDefaultFF) == 1)
	{
		SetConVarInt(g_hFriendlyFire, 1, true, false);
		SetConVarInt(g_hTeammatesAreEnemies, 1, true, false);
	}
	else
	{
		SetConVarInt(g_hFriendlyFire, 0, true, false);
		SetConVarInt(g_hTeammatesAreEnemies, 0, true, false);
	}
	
	if(g_bTagging)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientInGame(i) && IsPlayerAlive(i))
			{
				Command_UnTagPlayer(i, i, true);
			}
		}
	}
}
