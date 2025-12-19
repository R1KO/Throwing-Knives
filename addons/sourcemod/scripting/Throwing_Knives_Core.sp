#pragma semicolon 1

#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <cstrike>
#include <throwing_knives_core>

public Plugin myinfo = 
{
	name = "[CS S / CS GO] Throwing Knives Core",
	author = "R1KO", /* Сделано на основе плагинов от  meng и Bacardi */
	version = "1.7"
};

#define DMG_HEADSHOT		(1 << 30)

EngineVersion Engine_Version;

int g_iPointHurt;
int g_iDmgType;
int g_iTrailSprite;
int g_iBloodDecal;
ArrayList g_hThrownKnives;
bool g_bHeadshot[MAXPLAYERS+1];

int g_iPlayerKnives[MAXPLAYERS+1];
int g_iPlayerKniveCount[MAXPLAYERS+1];
int g_iPlayerKniveCountLimit[MAXPLAYERS+1];

int g_Cvar_iCount;
int g_Cvar_iLimit;
bool g_Cvar_bSteal;
float g_Cvar_fVelocity;
float g_Cvar_fDamage;
float g_Cvar_fHSDamage;
float g_Cvar_fModelScale;
float g_Cvar_fGravity;
float g_Cvar_fElasticity;
float g_Cvar_fMaxLifeTime;
bool g_Cvar_bTrails;

bool g_Cvar_bFF;

Handle g_hForward_OnKnifeDamage;
Handle g_hForward_OnKnifeThrow;
Handle g_hForward_OnKnifeThrowPost;
Handle g_hForward_OnKnifesGiven;
Handle g_hForward_OnKnifesTaken;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] szError, int err_max)
{
	g_hForward_OnKnifeDamage = CreateGlobalForward("TKC_OnKnifeDamage", ET_Hook, Param_Cell, Param_Cell, Param_Cell, Param_CellByRef, Param_CellByRef);
	g_hForward_OnKnifeThrow = CreateGlobalForward("TKC_OnKnifeThrow", ET_Hook, Param_Cell);
	g_hForward_OnKnifeThrowPost = CreateGlobalForward("TKC_OnKnifeThrowPost", ET_Hook, Param_Cell, Param_Cell);
	g_hForward_OnKnifesGiven = CreateGlobalForward("TKC_OnKnifesGiven", ET_Hook, Param_Cell, Param_CellByRef, Param_Cell);
	g_hForward_OnKnifesTaken = CreateGlobalForward("TKC_OnKnifesTaken", ET_Hook, Param_Cell, Param_CellByRef, Param_Cell);

	CreateNative("TKC_GetClientKnives", Native_GetClientKnives);
	CreateNative("TKC_SetClientKnives", Native_SetClientKnives);
	CreateNative("TKC_SetClientDefKnives", Native_SetClientDefKnives);
	CreateNative("TKC_GetClientKnivesLimit", Native_GetClientKnivesLimit);
	CreateNative("TKC_SetClientKnivesLimit", Native_SetClientKnivesLimit);
	CreateNative("TKC_SetClientDefKnivesLimit", Native_SetClientDefKnivesLimit);
	CreateNative("TKC_GiveClientKnives", Native_GiveClientKnives);
	CreateNative("TKC_TakeClientKnives", Native_TakeClientKnives);
	CreateNative("TKC_IsEntityThrowingKnife", Native_IsEntityThrowingKnife);

	MarkNativeAsOptional("GuessSDKVersion"); 
	MarkNativeAsOptional("GetEngineVersion");

	RegPluginLibrary("throwing_knives_core");

	return APLRes_Success;
}

public void OnPluginStart() 
{
	Engine_Version = GetEngineVersion();
	if (Engine_Version == Engine_Unknown)
	{
		SetFailState("Game is not supported!");
	}

	Handle hCvar;

	hCvar = FindConVar("mp_friendlyfire");
	HookConVarChange(hCvar, OnFFChange);
	g_Cvar_bFF = GetConVarBool(hCvar);

	hCvar = CreateConVar("tkc_count", "0", "RU  Сколько ножей будет получать игрок при возрождении (0 - Не выдывать, -1 - Бесконечно).\n\
												EN  Amount of knives players spawn with (0 = Disable, -1 = Infinite).", _, true, -1.0);
	HookConVarChange(hCvar, OnCountChange);
	g_Cvar_iCount = GetConVarInt(hCvar);

	hCvar = CreateConVar("tkc_limit", "-1", "RU  Сколько ножей может иметь игрок (-1 - Не ограничено).\n\
												EN  How many knives a player can have (-1 - No limit).", _, true, -1.0);
	HookConVarChange(hCvar, OnLimitChange);
	g_Cvar_iLimit = GetConVarInt(hCvar);

	hCvar = CreateConVar("tkc_steal", "1", "RU  Если включено атакующий получит ножи жертвы.\n\
												EN  If enabled, knife kills get the victims remaining knives.", _, true, 0.0, true, 1.0);
	HookConVarChange(hCvar, OnStealChange);
	g_Cvar_bSteal = GetConVarBool(hCvar);

	hCvar = CreateConVar("tkc_velocity", "2250.0", "RU  Скорость полёта ножа.\n\
												EN  Velocity (speed) adjustment.", _, true, 1.0);
	HookConVarChange(hCvar, OnVelocityChange);
	g_Cvar_fVelocity = GetConVarFloat(hCvar);

	hCvar = CreateConVar("tkc_damage", "57.0", "RU  Наносимый урон.\n\
												EN  Damage adjustment.", _, true, 1.0);
	HookConVarChange(hCvar, OnDamageChange);
	g_Cvar_fDamage = GetConVarFloat(hCvar);

	hCvar = CreateConVar("tkc_hsdamage", "127.0", "RU  Наносимый урон в голову.\n\
												EN  Headshot damage adjustment.", _, true, 0.0);
	HookConVarChange(hCvar, OnHSDamageChange);
	g_Cvar_fHSDamage = GetConVarFloat(hCvar);

	if (Engine_Version != Engine_SourceSDK2006)
	{
		hCvar = CreateConVar("tkc_modelscale", "1.0", "RU  Значение размера ножа (1.0 - норма).\n\
												EN  Knife size scale (1.0 - normal).", _, true, 0.0);
		HookConVarChange(hCvar, OnModelScaleChange);
		g_Cvar_fModelScale = GetConVarFloat(hCvar);
	}

	hCvar = CreateConVar("tkc_gravity", "1.0", "RU  Значение силы тяжести ножа (1.0 - норма).\n\
												EN  Knife gravity scale (1.0 - normal).", _, true, 0.0);
	HookConVarChange(hCvar, OnGravityChange);
	g_Cvar_fGravity = GetConVarFloat(hCvar);

	hCvar = CreateConVar("tkc_elasticity", "0.2", "RU  Значение эластичности.\n\
												EN  Knife elasticity.", _, true, 0.0);
	HookConVarChange(hCvar, OnElasticityChange);
	g_Cvar_fElasticity = GetConVarFloat(hCvar);

	hCvar = CreateConVar("tkc_maxlifetime", "1.5", "RU  Максимальное время жизни ножа (1 - 30 сек).\n\
												EN  Knife max life time (1 - 30 sec).", _, true, 1.0, true, 30.0);
	HookConVarChange(hCvar, OnMaxLifeTimeChange);
	g_Cvar_fMaxLifeTime = GetConVarFloat(hCvar);

	hCvar = CreateConVar("tkc_trails", "1", "RU  Эффект траектории ножа.\n\
												EN  Knive leave trail effect", _, true, 0.0, true, 1.0);
	HookConVarChange(hCvar, OnTrailsChange);
	g_Cvar_bTrails = GetConVarBool(hCvar);

	AutoExecConfig(true, "ThrowingKnives_Core");

	g_hThrownKnives = new ArrayList();

	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("weapon_fire", Event_WeaponFire);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);

	if (Engine_Version == Engine_CSGO)
	{
		g_iDmgType = DMG_SLASH|DMG_NEVERGIB;
	}
	else
	{
		g_iDmgType = DMG_BULLET|DMG_NEVERGIB;

		if (Engine_Version == Engine_SourceSDK2006)
		{
			HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
		}
	}
}

public void OnFFChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_bFF = GetConVarBool(hCvar);
}

public void OnCountChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_iCount = GetConVarInt(hCvar);
}

public void OnLimitChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_iLimit = GetConVarInt(hCvar);
}

public void OnStealChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_bSteal = GetConVarBool(hCvar);
}

public void OnVelocityChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_fVelocity = GetConVarFloat(hCvar);
}

public void OnDamageChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_fDamage = GetConVarFloat(hCvar);
}

public void OnHSDamageChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_fHSDamage = GetConVarFloat(hCvar);
}

public void OnModelScaleChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_fModelScale = GetConVarFloat(hCvar);
}

public void OnGravityChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_fGravity = GetConVarFloat(hCvar);
}

public void OnElasticityChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_fElasticity = GetConVarFloat(hCvar);
}

public void OnMaxLifeTimeChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_fMaxLifeTime = GetConVarFloat(hCvar);
}

public void OnTrailsChange(ConVar hCvar, const char[] szOldValue, const char[] szNewValue)
{
	g_Cvar_bTrails = GetConVarBool(hCvar);
}

public void OnMapStart()
{
	g_iTrailSprite = PrecacheModel(Engine_Version == Engine_CSGO ? "effects/blueblacklargebeam.vmt" : "sprites/bluelaser1.vmt");
	g_iBloodDecal = PrecacheDecal("sprites/blood.vmt");
}

public void OnClientPutInServer(int iClient)
{
	if(!IsClientSourceTV(iClient) && !IsClientReplay(iClient))
	{
		SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
		g_iPlayerKniveCount[iClient] = g_Cvar_iCount;
		g_iPlayerKniveCountLimit[iClient] = g_Cvar_iLimit;
	}
}

public Action OnTakeDamage(int iVictim, int &iAttacker, int &inflictor, float &damage, int &damagetype)
{
	if(0 < inflictor <= MaxClients && inflictor == iAttacker && damagetype == g_iDmgType)
	{
		g_bHeadshot[iAttacker] = false;
	}
}

public void Event_RoundEnd(Event hEvent, const char[] szEventName, bool bDontBroadcast)
{
	for(int i = 1; i <= MaxClients; ++i)
	{
		g_iPlayerKnives[i] = 0;
	}
}

public void Event_PlayerSpawn(Event hEvent, const char[] szEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
//	PrintToChat(iClient, "%s  %d", szEventName, g_iPlayerKniveCount[iClient]);

	if(g_iPlayerKniveCount[iClient] != 0)
	{
		int iCount, iDummy;
		iDummy = iCount = g_iPlayerKniveCount[iClient];

		switch (Forward_OnKnifesGiven(iClient, iCount, KNIFES_BY_DEFAULT))
		{
			case Plugin_Continue:
			{
				iCount = iDummy;
			}
			case Plugin_Handled, Plugin_Stop:
			{
				return;
			}
		}

		g_iPlayerKnives[iClient] = iCount;
	}
}

public Action Event_PlayerDeath(Event hEvent, const char[] szEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("attacker"));
	if(iClient)
	{
		char szWeapon[32];
		GetEventString(hEvent, "weapon", szWeapon, sizeof(szWeapon));

		if(StrContains(szWeapon, "knife", true) != -1 || StrContains(szWeapon, "bayonet", true) != -1)
		{
			SetEventBool(hEvent, "headshot", g_bHeadshot[iClient]);
			g_bHeadshot[iClient] = false;
	
			if(g_Cvar_bSteal && g_iPlayerKniveCount[iClient] != -1)
			{
				int iVictim = GetClientOfUserId(hEvent.GetInt("userid"));
				if(g_iPlayerKnives[iVictim] != -1 && g_iPlayerKniveCount[iVictim] != -1)
				{
					int iDummy, iCount;
					iCount = iDummy = g_iPlayerKnives[iVictim];
					if(g_iPlayerKnives[iVictim] + iCount > g_iPlayerKniveCountLimit[iVictim])
					{
						iCount = g_iPlayerKniveCountLimit[iVictim] - g_iPlayerKnives[iVictim];
					}
					Action eResult = Forward_OnKnifesGiven(iVictim, iCount, KNIFES_BY_STEAL);
					if(eResult > Plugin_Changed)
					{
						if(eResult == Plugin_Continue)
						{
							iCount = iDummy;
						}

						g_iPlayerKnives[iVictim] += iCount;

						PrintHintText(iVictim, "+%d ножа (Всего   %d)", iCount, g_iPlayerKnives[iVictim]);
					}
				}
			}
		}
	}

	return Plugin_Continue;
}

public void Event_WeaponFire(Event hEvent, const char[] szEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(hEvent.GetInt("userid"));
//	PrintToChat(iClient, "%s  '%s', %b && %b", szEventName, szWeapon, g_bHasAccess[iClient], HasClientKnives(iClient));
//	PrintToChat(iClient, "%s  %d", szEventName, g_iPlayerKnives[iClient]);
	if(g_iPlayerKnives[iClient] > 0 || g_iPlayerKnives[iClient] == -1)
	{
		char szWeapon[32];
		GetEventString(hEvent, "weapon", szWeapon, sizeof(szWeapon));
	//	PrintToChat(iClient, "weapon = '%s'", szWeapon);

	//	PrintToChat(iClient, "%s  '%s'", szEventName, szWeapon);
		if(StrContains(szWeapon, "knife", true) != -1 || StrContains(szWeapon, "bayonet", true) != -1)
		{
		//	PrintToChat(iClient, "StrContains");
			if(Forward_OnKnifeThrow(iClient))
			{
			//	PrintToChat(iClient, "Forward_OnKnifeThrow");
				RequestFrame(CreateKnife, iClient);
			}
		}
	}
}

int CreateKnife(int iClient)
{
	if(!IsClientInGame(iClient))
	{
		return;
	}

	int iKnife = CreateEntityByName("smokegrenade_projectile");
	DispatchKeyValue(iKnife, "classname", "throwing_knife");

	int iTeam = GetClientTeam(iClient);

	char szModel[PLATFORM_MAX_PATH];
	int iWeaponKnife = GetPlayerWeaponSlot(iClient, 2);
	if(iWeaponKnife != -1)
	{
		GetEntPropString(iWeaponKnife, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
		if(ReplaceString(szModel, sizeof(szModel), "v_knife_", "w_knife_", true) != 1)
		{
			szModel[0] = '\0';
		}
		else if(Engine_Version == Engine_CSGO && ReplaceString(szModel, sizeof(szModel), ".mdl", "_dropped.mdl", true) != 1)
		{
			szModel[0] = '\0';
		}
	}

	if(szModel[0] == '\0' || FileExists(szModel, true) == false)
	{
		if(Engine_Version == Engine_CSGO)
		{
			switch(iTeam)
			{
				case 2:	strcopy(szModel, sizeof(szModel), "models/weapons/w_knife_default_t_dropped.mdl");
				case 3:	strcopy(szModel, sizeof(szModel), "models/weapons/w_knife_default_ct_dropped.mdl");
			}
		}
		else
		{
			strcopy(szModel, sizeof(szModel), "models/weapons/w_knife_t.mdl");
		}
	}

	if(szModel[0] != '\0')
	{
		if(!IsModelPrecached(szModel))
		{
			PrecacheModel(szModel, true);
		}
		DispatchKeyValue(iKnife, "model", szModel);
	}

	if(!DispatchSpawn(iKnife))
	{
		return;
	}

	g_hThrownKnives.Push(EntIndexToEntRef(iKnife));

	SetEntPropEnt(iKnife, Prop_Send, "m_hOwnerEntity", iClient);
	SetEntPropEnt(iKnife, Prop_Send, "m_hThrower", iClient);
	SetEntProp(iKnife, Prop_Send, "m_iTeamNum", iTeam);

	if(Engine_Version != Engine_SourceSDK2006)
	{
		SetEntPropFloat(iKnife, Prop_Send, "m_flModelScale", g_Cvar_fModelScale);
	}
	SetEntPropFloat(iKnife, Prop_Send, "m_flElasticity", g_Cvar_fElasticity);
	SetEntPropFloat(iKnife, Prop_Data, "m_flGravity", g_Cvar_fGravity);

	float fOrigin[3], fAngles[3], sPos[3], fPlayerVelocity[3], fVelocity[3];
	GetClientEyePosition(iClient, fOrigin);
	GetClientEyeAngles(iClient, fAngles);

	GetAngleVectors(fAngles, sPos, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(sPos, 50.0);
	AddVectors(sPos, fOrigin, sPos);

	GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", fPlayerVelocity);
	GetAngleVectors(fAngles, fVelocity, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(fVelocity, g_Cvar_fVelocity);
	AddVectors(fVelocity, fPlayerVelocity, fVelocity);

	SetEntPropVector(iKnife, Prop_Data, "m_vecAngVelocity", view_as<float>({4000.0, 0.0, 0.0}));

	SetEntProp(iKnife, Prop_Data, "m_nNextThinkTick", -1);
	char szBuffer[PLATFORM_MAX_PATH];
	Format(szBuffer, sizeof(szBuffer), "!self,Kill,,%0.1f,-1", g_Cvar_fMaxLifeTime);
	DispatchKeyValue(iKnife, "OnUser1", szBuffer);
	AcceptEntityInput(iKnife, "FireUser1");

	if(g_Cvar_bTrails)
	{
		if(Engine_Version == Engine_CSGO)
		{
			TE_SetupBeamFollow(iKnife, g_iTrailSprite, 0, 0.5, 1.0, 0.1, 0, {255, 255, 255, 255});
		}
		else
		{
			TE_SetupBeamFollow(iKnife, g_iTrailSprite, 0, 0.5, 8.0, 1.0, 0, {255, 255, 255, 255});
		}

		TE_SendToAll();
	}

	TeleportEntity(iKnife, sPos, fAngles, fVelocity);
	SDKHook(iKnife, SDKHook_Touch, KnifeHit);
	
	Forward_OnKnifeThrowPost(iClient, iKnife);

	if(g_iPlayerKnives[iClient] != -1)
	{
		g_iPlayerKnives[iClient]--;
		PrintHintText(iClient, "Ножей осталось  %d", g_iPlayerKnives[iClient]);
	}
}

public Action KnifeHit(int iKnife, int iVictim)
{
	if(0 < iVictim && iVictim <= MaxClients && IsClientInGame(iVictim))
	{
		int iAttacker = GetEntPropEnt(iKnife, Prop_Send, "m_hThrower");

		if(!g_Cvar_bFF && GetClientTeam(iAttacker) == GetClientTeam(iVictim))
		{
			return Plugin_Continue;
		}

		float fVictimEye[3], fDamagePosition[3], fDamageForce[3];
		GetClientEyePosition(iVictim, fVictimEye);

		GetEntPropVector(iKnife, Prop_Data, "m_vecOrigin", fDamagePosition);
		GetEntPropVector(iKnife, Prop_Data, "m_vecVelocity", fDamageForce);

		if(GetVectorLength(fDamageForce) != 0.0)
		{
			float distance = GetVectorDistance(fDamagePosition, fVictimEye);
			g_bHeadshot[iAttacker] = distance <= 15.0;

			float fDamage;
			int iDmgType = g_iDmgType;

			bool bHeadshot = g_bHeadshot[iAttacker];
			if(g_bHeadshot[iAttacker])
			{
				fDamage = g_Cvar_fHSDamage;
			}
			else
			{
				fDamage = g_Cvar_fDamage;
			}
			
		//	PrintToChat(iAttacker, "fDamage = %.2f", fDamage);

			float fDummyDamage = fDamage;
			bool bDummyHeadshot = bHeadshot;

			switch(Forward_OnKnifeDamage(iAttacker, iVictim, iKnife, fDamage, bHeadshot))
			{
				case Plugin_Continue:
				{
					fDamage = fDummyDamage;
					bHeadshot = bDummyHeadshot;
				}
				case Plugin_Handled, Plugin_Stop:
				{
					AcceptEntityInput(iKnife, "Kill");
					return Plugin_Handled;
				}
			}
			
			if(bHeadshot)
			{
				iDmgType |= DMG_HEADSHOT;
			}

			if(Engine_Version == Engine_SourceSDK2006)
			{
				HurtClient(iVictim, iAttacker, fDamage, iDmgType, "weapon_knife");
			}
			else
			{
				int inflictor = GetPlayerWeaponSlot(iAttacker, 2);

				if(inflictor == -1)
				{
					inflictor = iAttacker;
				}

				SDKHooks_TakeDamage(iVictim, inflictor, iAttacker, fDamage, iDmgType, iKnife, fDamageForce, fDamagePosition);
			}

			TE_SetupBloodSprite(fDamagePosition, view_as<float>({0.0, 0.0, 0.0}), {255, 0, 0, 255}, 1, g_iBloodDecal, g_iBloodDecal);
			TE_SendToAll(0.0);

			SetVariantString("csblood");
			AcceptEntityInput(iKnife, "DispatchEffect");
			AcceptEntityInput(iKnife, "Kill");

			int ragdoll = GetEntPropEnt(iVictim, Prop_Send, "m_hRagdoll");
			if(ragdoll != -1)
			{
				ScaleVector(fDamageForce, 50.0);
				fDamageForce[2] = FloatAbs(fDamageForce[2]);
				SetEntPropVector(ragdoll, Prop_Send, "m_vecForce", fDamageForce);
				SetEntPropVector(ragdoll, Prop_Send, "m_vecRagdollVelocity", fDamageForce);
			}
		}
	}
	else if(g_hThrownKnives.FindValue(EntIndexToEntRef(iVictim)) != -1) // ножи столкнулись
	{
		SDKUnhook(iKnife, SDKHook_Touch, KnifeHit);
		float sPos[3], dir[3];
		GetEntPropVector(iKnife, Prop_Data, "m_vecOrigin", sPos);
		dir[0] = 0.0;
		dir[1] = 0.0;
		dir[2] = 0.0;
		TE_SetupArmorRicochet(sPos, dir);
		TE_SendToAll();

		DispatchKeyValue(iKnife, "OnUser1", "!self,Kill,,1.0,-1");
		AcceptEntityInput(iKnife, "FireUser1");
	}

	return Plugin_Continue;
}

public void OnEntityDestroyed(int iEntity)
{
	if(IsValidEdict(iEntity))
	{
		int index = g_hThrownKnives.FindValue(EntIndexToEntRef(iEntity));
		if(index != -1)
		{
			g_hThrownKnives.Erase(index);
		}
	}
}

public void Event_RoundFreezeEnd(Event hEvent, const char[] szEventName, bool bDontBroadcast)
{
	g_iPointHurt = CreateEntityByName("point_hurt");
	if (IsValidEntity(g_iPointHurt))
	{
		DispatchKeyValue(g_iPointHurt, "DamageTarget", "hurt");
		DispatchKeyValue(g_iPointHurt, "DamageType", "0");	   
		DispatchSpawn(g_iPointHurt);
	}
}

void HurtClient(int iClient, int iAttacker, float fDamage, int dmgtype, const char[] szWeapon)
{
	if (IsValidEntity(g_iPointHurt))
	{
		char szBuffer[8], szClientName[64];
		GetEntPropString(iClient, Prop_Data, "m_iName", szClientName, sizeof(szClientName));
		DispatchKeyValue(iClient, "targetname", "hurt");

		IntToString(dmgtype, szBuffer, sizeof(szBuffer));
		DispatchKeyValue(g_iPointHurt, "DamageType", 	szBuffer);

		FloatToString(fDamage, szBuffer, sizeof(szBuffer));
		DispatchKeyValue(g_iPointHurt, "Damage", szBuffer);

		DispatchKeyValue(g_iPointHurt, "classname", szWeapon);
		
		AcceptEntityInput(g_iPointHurt, "Hurt", iAttacker);
		DispatchKeyValue(iClient, "targetname", szClientName[0] ? szClientName : "nohurt");
	}
}

bool CheckClient(int iClient, char[] szError, int iLength)
{
	if (iClient < 1 || iClient > MaxClients)
	{
		FormatEx(szError, iLength, "Client index %i is invalid", iClient);
		return false;
	}
	else if (!IsClientInGame(iClient))
	{
		FormatEx(szError, iLength, "Client index %i is not in game", iClient);
		return false;
	}
	else if (IsFakeClient(iClient))
	{
		FormatEx(szError, iLength, "Client index %i is a bot", iClient);
		return false;
	}
	
	szError[0] = '\0';

	return true;
}

public int Native_GetClientKnives(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}
	
	if(GetNativeCell(2))
	{
		if(IsPlayerAlive(iClient))
		{
			return g_iPlayerKnives[iClient];
		}
	}
	else
	{
		return g_iPlayerKniveCount[iClient];
	}

	return 0;
}

public int Native_SetClientKnives(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}

	int iCount = GetNativeCell(2);
	if(iCount < -1)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid amount (%i)", iCount);
	}
	
//	LogMessage("Native_SetClientKnives  %N = %d (%b)", iClient, iCount, GetNativeCell(2));

	if(GetNativeCell(3))
	{
		if(IsPlayerAlive(iClient))
		{
		//	LogMessage("g_iPlayerKnives = %d", g_iPlayerKnives[iClient]);
			g_iPlayerKnives[iClient] = iCount;
			return g_iPlayerKnives[iClient];
		}
	}
	else
	{
	//	LogMessage("g_iPlayerKniveCount = %d", g_iPlayerKniveCount[iClient]);
		g_iPlayerKniveCount[iClient] = iCount;
		return g_iPlayerKniveCount[iClient];
	}

	return 0;
}

public int Native_SetClientDefKnives(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}

	g_iPlayerKniveCount[iClient] = g_Cvar_iCount;

	return g_iPlayerKniveCount[iClient];
}

public int Native_GetClientKnivesLimit(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}
	
	return g_iPlayerKniveCountLimit[iClient];
}

public int Native_SetClientKnivesLimit(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}

	int iLimit = GetNativeCell(2);
	if(iLimit < -1)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid amount (%i)", iLimit);
	}
	
//	LogMessage("Native_SetClientKnivesLimit  %N = %d (%b)", iClient, iLimit, GetNativeCell(2));
//	LogMessage("g_iPlayerKniveCountLimit = %d", g_iPlayerKniveCountLimit[iClient]);

	g_iPlayerKniveCountLimit[iClient] = iLimit;
//	LogMessage("g_iPlayerKniveCountLimit = %d", g_iPlayerKniveCountLimit[iClient]);

	return g_iPlayerKniveCountLimit[iClient];
}

public int Native_SetClientDefKnivesLimit(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}

	g_iPlayerKniveCountLimit[iClient] = g_Cvar_iLimit;

	return g_iPlayerKniveCountLimit[iClient];
}

public int Native_GiveClientKnives(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}

	int iCount = GetNativeCell(2);
	if(iCount < 0)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid amount (%i)", iCount);
	}
	
//	LogMessage("Native_GiveClientKnives  %N = %d (%b)", iClient, iCount, GetNativeCell(3));

	int iDummy = iCount;

	switch (Forward_OnKnifesGiven(iClient, iCount, KNIFES_BY_NATIVE))
	{
		case Plugin_Continue:
		{
			iCount = iDummy;
		}
		case Plugin_Handled, Plugin_Stop:
		{
			return false;
		}
	}

	if(GetNativeCell(3))
	{
		if(IsPlayerAlive(iClient) && g_iPlayerKnives[iClient] != -1)
		{
		//	LogMessage("g_iPlayerKnives = %d", g_iPlayerKnives[iClient]);
			g_iPlayerKnives[iClient] += iCount;
		//	LogMessage("g_iPlayerKnives = %d", g_iPlayerKnives[iClient]);
			return g_iPlayerKnives[iClient];
		}
	}
	else if(g_iPlayerKniveCount[iClient] != -1)
	{
	//	LogMessage("g_iPlayerKniveCount = %d", g_iPlayerKniveCount[iClient]);
		g_iPlayerKniveCount[iClient] += iCount;
	//	LogMessage("g_iPlayerKniveCount = %d", g_iPlayerKniveCount[iClient]);
		return g_iPlayerKniveCount[iClient];
	}

	return 0;
}

public int Native_TakeClientKnives(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	char szError[64];
	if (!CheckClient(iClient, szError, sizeof(szError)))
	{
		ThrowNativeError(SP_ERROR_NATIVE, szError);
	}

	int iCount = GetNativeCell(2);
	if(iCount < 1)
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Invalid amount (%i)", iCount);
	}

	int iDummy = iCount;

	switch (Forward_OnKnifesTaken(iClient, iCount, KNIFES_BY_NATIVE))
	{
		case Plugin_Continue:
		{
			iCount = iDummy;
		}
		case Plugin_Handled, Plugin_Stop:
		{
			return false;
		}
	}

	if(GetNativeCell(3))
	{
		if(IsPlayerAlive(iClient) && g_iPlayerKnives[iClient] != -1)
		{
			g_iPlayerKnives[iClient] -= iCount;
			if(g_iPlayerKnives[iClient] < 0)
			{
				g_iPlayerKnives[iClient] = 0;
			}
			return g_iPlayerKnives[iClient];
		}
	}
	else if(g_iPlayerKniveCount[iClient] != -1)
	{
		g_iPlayerKniveCount[iClient] -= iCount;
		if(g_iPlayerKniveCount[iClient] < 0)
		{
			g_iPlayerKniveCount[iClient] = 0;
		}
		return g_iPlayerKniveCount[iClient];
	}

	return 0;
}

public int Native_IsEntityThrowingKnife(Handle hPlugin, int iNumParams)
{
	int iEntity = GetNativeCell(1);

	if (iEntity < 1 || iEntity > 2048 || !IsValidEntity(iEntity))
	{
		ThrowNativeError(SP_ERROR_NATIVE, "Entity index %i is invalid", iEntity);
		return false;
	}

	return g_hThrownKnives.FindValue(EntIndexToEntRef(iEntity)) != -1;
}

Action Forward_OnKnifeDamage(int iAttacker, int iClient, int iKnife, float &fDamage, bool &bHeadShot)
{
	Action eResult = Plugin_Continue;
	
	Call_StartForward(g_hForward_OnKnifeDamage);
	Call_PushCell(iAttacker);
	Call_PushCell(iClient);
	Call_PushCell(iKnife);
	Call_PushCellRef(fDamage);
	Call_PushCellRef(bHeadShot);
	Call_Finish(eResult);
	
	return eResult;
}

bool Forward_OnKnifeThrow(int iClient)
{
	bool bResult = true;
	
	Call_StartForward(g_hForward_OnKnifeThrow);
	Call_PushCell(iClient);
	Call_Finish(bResult);

	return bResult;
}

void Forward_OnKnifeThrowPost(int iClient, int iEntity)
{
	Call_StartForward(g_hForward_OnKnifeThrowPost);
	Call_PushCell(iClient);
	Call_PushCell(iEntity);
	Call_Finish();
}

Action Forward_OnKnifesGiven(int iClient, int &iCount, int by_who)
{
	Action eResult = Plugin_Continue;
	
	Call_StartForward(g_hForward_OnKnifesGiven);
	Call_PushCell(iClient);
	Call_PushCellRef(iCount);
	Call_PushCell(by_who);
	Call_Finish(eResult);
	
	return eResult;
}

Action Forward_OnKnifesTaken(int iClient, int &iCount, int by_who)
{
	Action eResult = Plugin_Continue;
	
	Call_StartForward(g_hForward_OnKnifesTaken);
	Call_PushCell(iClient);
	Call_PushCellRef(iCount);
	Call_PushCell(by_who);
	Call_Finish(eResult);
	
	return eResult;
}
