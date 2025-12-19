#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <throwing_knives_core>
#include <cstrike>

#define COLLISION_GROUP_PUSHAWAY 11

public Plugin myinfo = 
{
	name = "[CS:S / CS:GO] Throwing Knives NoBlock",
	author = "DENZEL519&AI",
	description = "NoBlock для игроков с корректной регистрацией попаданий ножей",
	version = "1.8"
};

int g_iCollisionGroupOffset = -1;
bool g_bKnifeCoreLoaded = false;
EngineVersion g_EngineVersion;

public void OnPluginStart()
{
	g_iCollisionGroupOffset = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	if (g_iCollisionGroupOffset == -1)
	{
		SetFailState("Не удалось найти offset m_CollisionGroup!");
	}
	
	g_EngineVersion = GetEngineVersion();
	if (g_EngineVersion == Engine_Unknown)
	{
		SetFailState("Игра не поддерживается!");
	}
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("round_start", Event_RoundStart);
}

public void OnAllPluginsLoaded()
{
	g_bKnifeCoreLoaded = LibraryExists("throwing_knives_core");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "throwing_knives_core"))
	{
		g_bKnifeCoreLoaded = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "throwing_knives_core"))
	{
		g_bKnifeCoreLoaded = false;
	}
}

public void OnClientPutInServer(int client)
{
	if (!IsFakeClient(client) && !IsClientSourceTV(client) && !IsClientReplay(client))
	{
		RequestFrame(SetPlayerNoBlock, GetClientUserId(client));
	}
}

public void SetPlayerNoBlock(int userid)
{
	int client = GetClientOfUserId(userid);
	if (client > 0 && IsClientInGame(client))
	{
		// Устанавливаем COLLISION_GROUP_PUSHAWAY для игроков
		// Это позволяет им проходить сквозь друг друга
		SetEntData(client, g_iCollisionGroupOffset, COLLISION_GROUP_PUSHAWAY, 4, true);
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && IsClientInGame(client) && IsPlayerAlive(client))
	{
		SetEntData(client, g_iCollisionGroupOffset, COLLISION_GROUP_PUSHAWAY, 4, true);
	}
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && !IsFakeClient(i))
		{
			SetEntData(i, g_iCollisionGroupOffset, COLLISION_GROUP_PUSHAWAY, 4, true);
		}
	}
}

// Хукаем forward для корректировки определения headshot
public Action TKC_OnKnifeDamage(int attacker, int victim, int knife, float &damage, bool &headshot)
{
	if (!g_bKnifeCoreLoaded)
	{
		return Plugin_Continue;
	}
	
	// Получаем позицию ножа
	float knifePos[3];
	GetEntPropVector(knife, Prop_Data, "m_vecOrigin", knifePos);
	
	// Получаем позицию головы жертвы
	float victimEye[3];
	GetClientEyePosition(victim, victimEye);
	
	// Вычисляем расстояние от ножа до головы
	float distanceToHead = GetVectorDistance(knifePos, victimEye);
	
	// Если расстояние меньше или равно 15.0 - это точно headshot
	if (distanceToHead <= 15.0)
	{
		headshot = true;
		
		// Получаем урон для headshot
		ConVar cvarHSDamage = FindConVar("tkc_hsdamage");
		if (cvarHSDamage != null)
		{
			damage = cvarHSDamage.FloatValue;
		}
		
		return Plugin_Changed;
	}
	
	// Если расстояние больше 15.0, но меньше 25.0 - используем trace ray для более точного определения
	if (distanceToHead <= 25.0)
	{
		// Выполняем trace ray от ножа к голове для более точного определения
		float direction[3];
		SubtractVectors(victimEye, knifePos, direction);
		NormalizeVector(direction, direction);
		
		float traceEnd[3];
		ScaleVector(direction, distanceToHead + 10.0);
		AddVectors(knifePos, direction, traceEnd);
		
		Handle trace = TR_TraceRayFilterEx(knifePos, traceEnd, MASK_SHOT_HULL, RayType_EndPoint, TraceFilterHeadshot, knife);
		
		if (TR_DidHit(trace))
		{
			float hitPos[3];
			TR_GetEndPosition(hitPos, trace);
			float finalDistance = GetVectorDistance(hitPos, victimEye);
			
			if (finalDistance <= 15.0)
			{
				headshot = true;
				ConVar cvarHSDamage = FindConVar("tkc_hsdamage");
				if (cvarHSDamage != null)
				{
					damage = cvarHSDamage.FloatValue;
				}
				CloseHandle(trace);
				return Plugin_Changed;
			}
		}
		
		CloseHandle(trace);
	}
	
	return Plugin_Continue;
}

public bool TraceFilterHeadshot(int entity, int contentsMask, any knife)
{
	// Игнорируем сам нож
	if (entity == knife)
	{
		return false;
	}
	
	// Игнорируем другие ножи
	if (entity > 0 && entity <= 2048)
	{
		char classname[64];
		if (GetEdictClassname(entity, classname, sizeof(classname)) && StrEqual(classname, "throwing_knife"))
		{
			return false;
		}
	}
	
	return true;
}

// Хукаем forward для установки правильной модели ножа
public void TKC_OnKnifeThrowPost(int client, int entity)
{
	if (!g_bKnifeCoreLoaded)
	{
		return;
	}
	
	if (!IsValidEntity(entity))
	{
		return;
	}
	
	// Получаем модель ножа из оружия игрока
	char sModel[PLATFORM_MAX_PATH];
	int iWeaponKnife = GetPlayerWeaponSlot(client, 2);
	
	if (iWeaponKnife != -1)
	{
		GetEntPropString(iWeaponKnife, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
		
		// Преобразуем v_ модель в w_ модель
		if (ReplaceString(sModel, sizeof(sModel), "v_knife_", "w_knife_", true) == 1)
		{
			// Для CS:GO нужно добавить "_dropped" перед расширением
			if (g_EngineVersion == Engine_CSGO)
			{
				if (ReplaceString(sModel, sizeof(sModel), ".mdl", "_dropped.mdl", true) != 1)
				{
					sModel[0] = '\0';
				}
			}
		}
		else
		{
			sModel[0] = '\0';
		}
	}
	
	// Если модель не найдена или файл не существует, используем стандартную модель
	if (sModel[0] == '\0' || !FileExists(sModel, true))
	{
		int iTeam = GetClientTeam(client);
		
		if (g_EngineVersion == Engine_CSGO)
		{
			switch (iTeam)
			{
				case 2: strcopy(sModel, sizeof(sModel), "models/weapons/w_knife_default_t_dropped.mdl");
				case 3: strcopy(sModel, sizeof(sModel), "models/weapons/w_knife_default_ct_dropped.mdl");
			}
		}
		else
		{
			strcopy(sModel, sizeof(sModel), "models/weapons/w_knife_t.mdl");
		}
	}
	
	// Устанавливаем модель на сущность ножа
	if (sModel[0] != '\0' && IsModelPrecached(sModel))
	{
		SetEntityModel(entity, sModel);
	}
	else
	{
		// Если модель не закеширована, кешируем и устанавливаем
		PrecacheModel(sModel, true);
		SetEntityModel(entity, sModel);
	}
}
