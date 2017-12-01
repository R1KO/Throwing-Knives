#pragma semicolon 1

#include <sourcemod>
#include <throwing_knives_core>

public Plugin:myinfo = 
{
	name = "[Throwing Knives] Admins Knives",
	author = "R1KO",
	version = "1.0"
};

new 		g_Cvar_iAdminFlag;
new 		g_Cvar_iCount;
new 		g_Cvar_iLimit;

public OnPluginStart() 
{
	decl Handle:hCvar;
	
	hCvar = CreateConVar("tk_admin_flag", "", "RU: Админ флаг для доступа (0 или \"\" - Для всех).\n\
												EN: Admin flag for access  (0 or \"\" - For all).", _, true, -1.0);
	HookConVarChange(hCvar, OnAdminFlagChange);
	g_Cvar_iAdminFlag = GetConVarAdminFlag(hCvar);

	hCvar = CreateConVar("tk_admin_count", "0", "RU: Сколько ножей будет получать игрок при возрождении (0 - Не выдывать, -1 - Бесконечно).\n\
												EN: Amount of knives players spawn with (0 = Disable, -1 = Infinite).", _, true, -1.0);
	HookConVarChange(hCvar, OnCountChange);
	g_Cvar_iCount = GetConVarInt(hCvar);

	hCvar = CreateConVar("tk_admin_limit", "-1", "RU: Сколько ножей может иметь игрок (-1 - Не ограничено).\n\
												EN: How many knives a player can have (-1 - No limit).", _, true, -1.0);
	HookConVarChange(hCvar, OnLimitChange);
	g_Cvar_iLimit = GetConVarInt(hCvar);

	AutoExecConfig(true, "TK_AdminsKnives");
}

public OnAdminFlagChange(Handle:hCvar, const String:sOldValue[], const String:sNewValue[])		g_Cvar_iAdminFlag = GetConVarAdminFlag(hCvar);
public OnCountChange(Handle:hCvar, const String:sOldValue[], const String:sNewValue[])			g_Cvar_iCount = GetConVarInt(hCvar);
public OnLimitChange(Handle:hCvar, const String:sOldValue[], const String:sNewValue[])		g_Cvar_iLimit = GetConVarInt(hCvar);

GetConVarAdminFlag(Handle:hCvar)
{
	decl String:sBuffer[16];
	GetConVarString(hCvar, sBuffer, sizeof(sBuffer));
	return ReadFlagString(sBuffer);
}

public OnClientPostAdminCheck(iClient)
{
	if(!IsFakeClient(iClient))
	{
		CheckClient(iClient);
	}
}

public OnRebuildAdminCache(AdminCachePart:part)
{
	for(new i = 1; i <= MaxClients; ++i)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			CheckClient(i);
		}
	}
}

CheckClient(iClient)
{
	if((g_Cvar_iAdminFlag && GetUserFlagBits(iClient) & g_Cvar_iAdminFlag))
	{
		new iLimit = TKC_GetClientKnivesLimit(iClient);
		new iKnives = TKC_GetClientKnives(iClient, false);
		if(iLimit != -1 && (iLimit < g_Cvar_iLimit || g_Cvar_iLimit == -1))
		{
			TKC_SetClientKnivesLimit(iClient, g_Cvar_iLimit);
		}
		if(iKnives != -1 && (iKnives < g_Cvar_iCount || g_Cvar_iCount == -1))
		{
			TKC_SetClientKnives(iClient, g_Cvar_iCount, false);
		}
	}
}