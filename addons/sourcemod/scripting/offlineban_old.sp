#pragma semicolon 1
//#pragma tabsize 0

#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <adminmenu>

#define MAX_STEAMID_LENGTH 32
#define MAX_IP_LENGTH 64

#define PREFIX "[Offline Ban]"
#define DEBUG 0 	//тестовый режим

new String:g_sTarget[MAXPLAYERS+1][4][125];
#define TNAME 0 	// Name
#define TIP 1		// ip
#define TSTEAMID 2 	// steam
#define TREASON 3 	// Reason

new g_iTarget[MAXPLAYERS+1][2];
#define TID 0  		// id
#define TTIME 1		// time

new	g_iServerID = -1;

new Handle:g_hSQLiteDB = INVALID_HANDLE,
	Handle:g_hDatabase = INVALID_HANDLE;

new Handle:g_tmAdminMenu,
	Handle:g_mReasonMenu,
	Handle:g_mHackingMenu,
	Handle:g_mTimeMenu;

new String:g_sServerIP[32], 
	String:g_sServerPort[8],
	String:g_sLogFile[256],
	String:g_sDatabasePrefix[10] = "sb",
	String:g_sQuery[MAXPLAYERS+1][256];
	
new bool:g_bSourcebans = false,
	bool:g_bSayReason[MAXPLAYERS+1] = false;
	
new String:g_sFormatTime[125],
	g_iMaxStoredPlayers,
	g_iMenuItems,
	bool:g_bMapClear = false,
	bool:g_bDelConPlayers = false,
	bool:g_bMenuNewLine = false;

new Handle:g_smcConfigParser;

new g_iConfigState;
#define	CONFCONFIG	1
#define CONFTIME	2
#define CONFREASON	3
#define	CONFHACKING	4

public Plugin:myinfo = 
{
	name = "Offline Ban list",
	author = "Grey™ & R1KO",
	description = "For to sm old",
	version = "2.5.0",
	url = "hlmod.ru Skype: wolf-1-ser"
};

public OnPluginStart() 
{
	LoadTranslations("offlineban.phrases");
	
	RegAdminCmd("sm_offban_clear", CommandClearBan, ADMFLAG_ROOT, "Clear history");
	RegConsoleCmd("say", ChatHook);
	RegConsoleCmd("say_team", ChatHook);

	BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/offlineban.log");
	
	OffMenu();

	new String:sError[256];
	g_hSQLiteDB = SQLite_UseDatabase("offlineban", sError, sizeof(sError));
	if (g_hSQLiteDB == INVALID_HANDLE)
		SetFailState("Database failure (%s)", sError);

	CreateOBTables();
}

public OnAllPluginsLoaded()
{
	if (LibraryExists("sourcebans"))
	{
		g_bSourcebans = true;
		ConectSourceBan();
	}
	else
	{
		g_bSourcebans = false;
		PrintToServer("%s Sourcebans OFF", PREFIX);
	}
}

public OnLibraryAdded(const String:sName[])
{
	if (StrEqual(sName, "sourcebans"))
	{
		g_bSourcebans = true;
		ConectSourceBan();
	}
}

public OnLibraryRemoved(const String:sName[])
{
	if (StrEqual(sName, "sourcebans"))
	{
		g_bSourcebans = false;
		PrintToServer("%s Sourcebans OFF", PREFIX);
	}
	if (StrEqual(sName, "adminmenu")) 
		g_tmAdminMenu = INVALID_HANDLE;
}

ConectSourceBan()
{
	PrintToServer("%s Sourcebans ON", PREFIX);
	new String:sError[256];
	g_hDatabase = SQL_Connect("sourcebans", false, sError, sizeof(sError));
	if (g_hDatabase == INVALID_HANDLE && g_bSourcebans)
		SetFailState("Database failure (%s)", sError);
	
	InsertServerInfo();
}

public Action:CommandClearBan(iClient, args)
{
	Clear_histories();

	PrintToChat(iClient, "%T",  "Clear history", iClient);
	
	return Plugin_Handled;
}

public OnMapStart()
{ 
	ReadConfig();
	
	if(g_bMapClear) 
		Clear_histories();
}

Clear_histories()
{
	new String:sQuery[64];
	FormatEx(sQuery, sizeof(sQuery), "DROP TABLE  `offlineban`");
	SQL_TQuery(g_hSQLiteDB, SQL_Callback_DeleteClients, sQuery);
}

public SQL_Callback_DeleteClients(Handle:db, Handle:dbRs, const String:sError[], any:iClient)
{
	if (sError[0])
		LogToFile(g_sLogFile, "SQL_Callback_DeleteClients: %s", sError);
	else
		CreateOBTables();
}

public Action:ChatHook(iClient, iArgs)
{
	if (g_bSayReason[iClient])
	{
		new String:sReason[512];
		GetCmdArgString(sReason, sizeof(sReason));
		StripQuotes(sReason);
		strcopy(g_sTarget[iClient][TREASON], sizeof(g_sTarget[][]), sReason);
	#if DEBUG
		LogToFile(g_sLogFile,"Chat Reason: %s", sReason);
	#endif
		PrintToChat(iClient, "%T", "Own reason", iClient, sReason);
		g_bSayReason[iClient] = false;
		CreateBanSB(iClient);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// удаление игроков вошедших в игру
public OnClientPostAdminCheck(iClient)
{
	if (!g_bDelConPlayers || !IsClientInGame(iClient) || IsFakeClient(iClient)) 
		return;

	decl String:sSteamID[MAX_STEAMID_LENGTH],
		 String:sQuery[256];
	
	GetClientAuthString(iClient, sSteamID, sizeof(sSteamID));
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `offlineban` WHERE `auth` = '%s'", sSteamID);
	SQL_TQuery(g_hSQLiteDB, SQL_Callback_DeleteClient, sQuery);
}

public SQL_Callback_DeleteClient(Handle:db, Handle:dbRs, const String:sError[], any:iClient)
{
	if (sError[0])
		LogToFile(g_sLogFile, "SQL_Callback_DeleteClient: %s", sError);
}
 //зачисление в список игроков вышедших из игры
public OnClientDisconnect(iClient) 
{
	if (!IsClientInGame(iClient) || IsFakeClient(iClient)) 
		return;

	if (GetUserAdmin(iClient) != INVALID_ADMIN_ID) 
		return;

	decl String:sSteamID[MAX_STEAMID_LENGTH],
		 String:sName[MAX_NAME_LENGTH],
		 String:sEName[MAX_NAME_LENGTH*2+1],
		 String:sIP[MAX_IP_LENGTH],
		 String:sQuery[512];
		 
	g_bSayReason[iClient] = false;

	GetClientAuthString(iClient, sSteamID, sizeof(sSteamID));
	GetClientName(iClient, sName, sizeof(sName));
	GetClientIP(iClient, sIP, sizeof(sIP));

	SQL_EscapeString(g_hSQLiteDB, sName, sEName, sizeof(sEName));

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `offlineban` (auth, ip, name, disc_time) VALUES \
										('%s', '%s', '%s', %i)", sSteamID, sIP, sEName, GetTime());
	SQL_TQuery(g_hSQLiteDB, SQL_Callback_AddClient, sQuery);

#if DEBUG
	decl String:sTime[64];

	FormatTime(sTime, sizeof(sTime), g_sFormatTime, GetTime());
	LogToFile(g_sLogFile,"New: %s %s - %s ; %s.", sName, sSteamID, sIP, sTime);
#endif
}

public SQL_Callback_AddClient(Handle:db, Handle:dbRs, const String:sError[], any:iClient)
{
	if (dbRs == INVALID_HANDLE || sError[0])
		LogToFile(g_sLogFile, "SQL_Callback_AddClient: %s", sError);
}
//меню
OffMenu()
{
	g_mReasonMenu = CreateMenu(MenuHandler_MenuReason);
	SetMenuExitBackButton(g_mReasonMenu, true);

	g_mHackingMenu = CreateMenu(MenuHandler_MenuHacking);
	SetMenuExitBackButton(g_mHackingMenu, true);

	g_mTimeMenu = CreateMenu(MenuHandler_MenuTime);
	SetMenuExitBackButton(g_mTimeMenu, true);
}

public OnAdminMenuReady(Handle:hTopmenu)
{
	if (hTopmenu == g_tmAdminMenu)
		return;

	g_tmAdminMenu = hTopmenu;
	new TopMenuObject:player_commands = FindTopMenuCategory(g_tmAdminMenu, ADMINMENU_PLAYERCOMMANDS);
	if (player_commands != INVALID_TOPMENUOBJECT)
		AddToTopMenu(g_tmAdminMenu, "OfflineBans", TopMenuObject_Item, AdminMenu_Ban, player_commands, "OfflineBans", ADMFLAG_BAN);
}

public AdminMenu_Ban(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, iClient, String:sBuffer[], maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption: FormatEx(sBuffer, maxlength, "%T", "OfflineBansTitle", iClient);
		case TopMenuAction_SelectOption: ShowBanList(iClient);
	}
}
//меню выбора игрока
ShowBanList(iClient) 
{
	FormatEx(g_sQuery[iClient], sizeof(g_sQuery[]), "SELECT `id`, `auth`, `name`, `disc_time` FROM `offlineban` ORDER BY `id` DESC LIMIT %d;", g_iMaxStoredPlayers);
	SQL_TQuery(g_hSQLiteDB, SendMenuCallback, g_sQuery[iClient], iClient, DBPrio_High);
}

public SendMenuCallback(Handle:db, Handle:dbRs, const String:sError[], any:iClient)
{
	if(dbRs == INVALID_HANDLE)
	{
		LogError("Error loading offline ban (%s)", sError);
		return;
	}

	if(!IsClientInGame(iClient))
		return;
	
	new Handle:hMenu = CreateMenu(MenuHandler_BanList);
	SetMenuTitle(hMenu, "%T", "SelectPlayerTitle", iClient);
	decl String:sTitle[128];

	if (SQL_GetRowCount(dbRs))
	{
		decl String:sName[MAX_NAME_LENGTH],
			 String:sSteamID[MAX_STEAMID_LENGTH],
			 String:sID[12],
			 String:sTime[64];

		while(SQL_FetchRow(dbRs))
		{
			SQL_FetchString(dbRs, 0, sID, sizeof(sID));
			SQL_FetchString(dbRs, 1, sSteamID, sizeof(sSteamID));
			SQL_FetchString(dbRs, 2, sName, sizeof(sName));
			FormatTime(sTime, sizeof(sTime), g_sFormatTime, SQL_FetchInt(dbRs, 3));
			if (g_bMenuNewLine)
			{
				switch(g_iMenuItems)
				{
					case 1:	FormatEx(sTitle, sizeof(sTitle), "%s\n%s", sName, sTime);
					case 2: FormatEx(sTitle, sizeof(sTitle), "%s\n%s", sName, sSteamID); 
					case 3: FormatEx(sTitle, sizeof(sTitle), "%s\n%s (%s)", sName, sSteamID, sTime); 
				}
			}
			else
			{
				switch(g_iMenuItems)
				{
					case 1:	FormatEx(sTitle, sizeof(sTitle), "%s (%s)", sName, sTime);
					case 2: FormatEx(sTitle, sizeof(sTitle), "%s (%s)", sName, sSteamID); 
					case 3: FormatEx(sTitle, sizeof(sTitle), "%s - %s (%s)", sName, sSteamID, sTime); 
				}
			}
			AddMenuItem(hMenu, sID, sTitle);
		#if DEBUG
			LogToFile(g_sLogFile,"Menu: %s, %s - %s", sID, sSteamID, sTitle);
		#endif
		}
	}
	else
	{
		FormatEx(sTitle, sizeof(sTitle), "%T", "No players history", iClient);
		AddMenuItem(hMenu, "", sTitle, ITEMDRAW_DISABLED);	
	}
	
	SetMenuExitBackButton(hMenu, true);
	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
}

public MenuHandler_BanList(Handle:Mmenu, MenuAction:mAction, iClient, iSlot) 
{
	switch(mAction)
	{
		case MenuAction_End: CloseHandle(Mmenu);
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != INVALID_HANDLE)
				DisplayTopMenu(g_tmAdminMenu, iClient, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			decl String:sID[12];
			GetMenuItem(Mmenu, iSlot, sID, sizeof(sID));
			g_iTarget[iClient][TID] = StringToInt(sID);
			FormatEx(g_sQuery[iClient], sizeof(g_sQuery[]), "SELECT `auth`, `ip`, `name` FROM `offlineban` WHERE `id` = '%i'", g_iTarget[iClient][TID]);
			new Handle:dbRs = SQL_Query(g_hSQLiteDB, g_sQuery[iClient]);

			if (g_hSQLiteDB == INVALID_HANDLE || dbRs == INVALID_HANDLE)
			{
				LogToFile(g_sLogFile, "Database, dbRs failure, Name");
				return;
			}
			
			if (SQL_FetchRow(dbRs))
			{
				SQL_FetchString(dbRs, 0, g_sTarget[iClient][TSTEAMID], sizeof(g_sTarget[][]));
				SQL_FetchString(dbRs, 1, g_sTarget[iClient][TIP], sizeof(g_sTarget[][]));
				SQL_FetchString(dbRs, 2, g_sTarget[iClient][TNAME], sizeof(g_sTarget[][]));
			}
			else
			{
				PrintToChat(iClient, "%T", "Failed to player", iClient, g_sTarget[iClient][TNAME]);
				return;
			}
			
			CloseHandle(dbRs);

		#if DEBUG
			LogToFile(g_sLogFile,"Menu BanList: %i , %s ", g_iTarget[iClient][TID], g_sTarget[iClient][TNAME]);
		#endif

			ShowBanTimeMenu(iClient);
		}
	}
}

//меню выбора времени бана
ShowBanTimeMenu(iClient)
{
	decl String:sTitle[128],
		 String:sBuffer[12];

	SetMenuTitle(g_mTimeMenu, "%T - %s", "SelectTimeTitle", iClient, g_sTarget[iClient][TNAME]);

	new iCount = GetMenuItemCount(g_mTimeMenu);
	for (new i = 0; i < iCount; i++)
	{
		GetMenuItem(g_mTimeMenu, i, sBuffer, sizeof(sBuffer), _, sTitle, sizeof(sTitle));
	#if DEBUG
		LogToFile(g_sLogFile,"Menu time: %i , %s, %s", i, sBuffer, sTitle);
	#endif
		if(StringToInt(sBuffer) == 0)
		{
		#if DEBUG
			LogToFile(g_sLogFile,"Menu time: yes %i , %s, %s", i, sBuffer, sTitle);
		#endif
			if (GetUserFlagBits(iClient) & (ADMFLAG_UNBAN | ADMFLAG_ROOT))
			{
				RemoveMenuItem(g_mTimeMenu, i);
				InsertMenuItem(g_mTimeMenu, i, sBuffer, sTitle);
			}
			else
			{
				RemoveMenuItem(g_mTimeMenu, i);
				InsertMenuItem(g_mTimeMenu, i, sBuffer, sTitle, ITEMDRAW_DISABLED);
			}
			break;
		}
	}

	DisplayMenu(g_mTimeMenu, iClient, MENU_TIME_FOREVER);
}

public MenuHandler_MenuTime(Handle:Mmenu, MenuAction:mAction, iClient, iSlot) 
{
	switch(mAction)
	{
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != INVALID_HANDLE)
				ShowBanList(iClient);
		}
		case MenuAction_Select:
		{
			decl String:sInfo[12];
			GetMenuItem(Mmenu, iSlot, sInfo, sizeof(sInfo));
			g_iTarget[iClient][TTIME] = StringToInt(sInfo);
		#if DEBUG
			LogToFile(g_sLogFile,"Menu Time: %s", sInfo);
		#endif

			ShowBanReasonMenu(iClient);
		}
	}
}

//меню выбора причины бана
ShowBanReasonMenu(iClient)
{
	SetMenuTitle(g_mReasonMenu, "%T - %s", "SelectReasonTitle", iClient, g_sTarget[iClient][TNAME]);
	DisplayMenu(g_mReasonMenu, iClient, MENU_TIME_FOREVER);
}

public MenuHandler_MenuReason(Handle:Mmenu, MenuAction:mAction, iClient, iSlot) 
{
	switch(mAction)
	{
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != INVALID_HANDLE)
				ShowBanTimeMenu(iClient);
		}
		case MenuAction_Select:
		{
			decl String:sInfo[128];
			GetMenuItem(Mmenu, iSlot, sInfo, sizeof(sInfo));
			if(StrEqual("Hacking", sInfo))
			{
				ShowBanHackingMenu(iClient);
				return;
			}
			if(StrEqual("Own Reason", sInfo))
			{
				PrintToChat(iClient, "%T", "Say reason", iClient);
				g_bSayReason[iClient] = true;
				return;
			}
			strcopy(g_sTarget[iClient][TREASON], sizeof(sInfo), sInfo);
		#if DEBUG
			LogToFile(g_sLogFile,"Menu Reason: %s", sInfo);
		#endif
			CreateBanSB(iClient);
		}
	}
}

ShowBanHackingMenu(iClient)
{
	SetMenuTitle(g_mHackingMenu, "%T - %s", "SelectReasonTitle", iClient, g_sTarget[iClient][TNAME]);
	DisplayMenu(g_mHackingMenu, iClient, MENU_TIME_FOREVER);
}

public MenuHandler_MenuHacking(Handle:Mmenu, MenuAction:mAction, iClient, iSlot) 
{
	switch(mAction)
	{
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != INVALID_HANDLE)
				ShowBanReasonMenu(iClient);
		}
		case MenuAction_Select:
		{
			decl String:sInfo[128];
			GetMenuItem(Mmenu, iSlot, sInfo, sizeof(sInfo));
			strcopy(g_sTarget[iClient][TREASON], sizeof(sInfo), sInfo);
		#if DEBUG
			LogToFile(g_sLogFile,"Menu Hacking: %s", sInfo);
		#endif

			CreateBanSB(iClient);
		}
	}
}	

//занесение бана в бд
CreateBanSB(iClient)
{
	if(!g_bSourcebans)
	{
		CreateBan(iClient);
		return;
	}

	decl String:sBanName[MAX_NAME_LENGTH*2+1],
		 String:sReason[200],
		 String:sQuery[1024],
		 String:sAdmin_SteamID[MAX_STEAMID_LENGTH],
		 String:sAdminIp[MAX_IP_LENGTH],
		 String:sQueryAdmin[156],
		 String:sServer[256];

	if (iClient)
	{
		GetClientAuthString(iClient, sAdmin_SteamID, sizeof(sAdmin_SteamID));
		GetClientIP(iClient, sAdminIp, sizeof(sAdminIp));
		FormatEx(sQueryAdmin, sizeof(sQueryAdmin), "IFNULL ((SELECT `aid` FROM %s_admins WHERE `authid` REGEXP '^STEAM_[0-9]:%s$'), 0)", g_sDatabasePrefix, sAdmin_SteamID[8]);
	}
	else
	{
		strcopy(sAdmin_SteamID, sizeof(sAdmin_SteamID), "STEAM_ID_SERVER");
		strcopy(sAdminIp, sizeof(sAdminIp), g_sServerIP);
	}

	new iTime = g_iTarget[iClient][TTIME]*60;

	SQL_EscapeString(g_hDatabase, g_sTarget[iClient][TNAME], sBanName, sizeof(sBanName));
#if DEBUG
	LogToFile(g_sLogFile,"name do %s : posle %s", g_sTarget[iClient][TNAME], sBanName);
#endif
	FormatEx(sReason, sizeof(sReason), "%s %s", PREFIX, g_sTarget[iClient][TREASON]);

	if(g_iServerID == -1)
		FormatEx(sServer, sizeof(sServer), "IFNULL ((SELECT `sid` FROM `%s_servers` WHERE `ip` = '%s' AND `port` = '%s' LIMIT 1), 0)", g_sDatabasePrefix, g_sServerIP, g_sServerPort);
	else
		IntToString(g_iServerID, sServer, sizeof(sServer));

	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `%s_bans` (`ip`, `authid`, `name`, `created`, `ends`, `length`, `reason`, `aid`, `adminIp`, `sid`, `country`) \
			VALUES ('%s', '%s', '%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + %d, %d, '%s', %s, '%s', %s, ' ')", 
			g_sDatabasePrefix, g_sTarget[iClient][TIP], g_sTarget[iClient][TSTEAMID], sBanName, iTime, iTime, sReason, sQueryAdmin, sAdminIp, sServer);

	SQL_SetCharset(g_hDatabase, "utf8");
	SQL_TQuery(g_hDatabase, VerifyInsert, sQuery, iClient, DBPrio_High);
#if DEBUG
	LogToFile(g_sLogFile,": %s", sQuery);
#endif
	LogAction(iClient, -1, "\"%L\" banned \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
							g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
}

//ответ занисения в бд бана(прошёл или нет)
public VerifyInsert(Handle:db, Handle:dbRs, const String:sError[], any:iClient)
{
	if (dbRs == INVALID_HANDLE || sError[0])
	{
		LogToFile(g_sLogFile, "Verify Insert Query Failed: %s", sError);
		if (iClient > 0)
			PrintToChat(iClient, "%T", "Failed to ban", iClient, g_sTarget[iClient][TNAME]);
	}
	else
	{
		decl String:sQuery[125];
		if (iClient > 0)
			PrintToChat(iClient, "%T", "Added to ban", iClient, g_sTarget[iClient][TNAME]);
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `offlineban` WHERE `id` = '%i';", g_iTarget[iClient][TID]);
		SQL_TQuery(g_hSQLiteDB, SQL_Callback_DeleteClient, sQuery);
	}
}

CreateBan(iClient)
{
	if(BanIdentity(g_sTarget[iClient][TSTEAMID], g_iTarget[iClient][TTIME], BANFLAG_AUTHID, g_sTarget[iClient][TREASON], ""))
		PrintToChat(iClient, "%T", "Added to ban", iClient, g_sTarget[iClient][TNAME]);
	else
		PrintToChat(iClient, "%T", "Failed to ban", iClient, g_sTarget[iClient][TNAME]);
	LogAction(iClient, -1, "\"%L\" banned \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
							g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
}

CreateOBTables()
{
	SQL_LockDatabase(g_hSQLiteDB);
	SQL_FastQuery(g_hSQLiteDB, "PRAGMA encoding = \"UTF-8\"");
	if(SQL_FastQuery(g_hSQLiteDB, "CREATE TABLE IF NOT EXISTS `offlineban` (`id` INTEGER PRIMARY KEY AUTOINCREMENT, \
										`auth` VARCHAR(32) UNIQUE ON CONFLICT REPLACE,\
										`ip` VARCHAR(24) NOT NULL, \
										`name` VARCHAR(64) DEFAULT 'unknown',\
										`disc_time` NUMERIC NOT NULL);") == false)
	{
		decl String:sError[256];
		SQL_GetError(g_hSQLiteDB, sError, sizeof(sError));
		SetFailState("%s Query CREATE TABLE failed! %s", PREFIX, sError);
	}
	SQL_UnlockDatabase(g_hSQLiteDB);
}

//получение значений конфига сб
ReadConfig()
{
	if (g_smcConfigParser == INVALID_HANDLE)
	{
		g_smcConfigParser = SMC_CreateParser();
		SMC_SetReaders(g_smcConfigParser, ReadConfig_NewSection, ReadConfig_KeyValue, ReadConfig_EndSection);
	}

	decl String:sConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/offban.cfg");

	if(g_mReasonMenu != INVALID_HANDLE)
		RemoveAllMenuItems(g_mReasonMenu);
	if(g_mHackingMenu != INVALID_HANDLE)
		RemoveAllMenuItems(g_mHackingMenu);
	if(g_mTimeMenu != INVALID_HANDLE)
		RemoveAllMenuItems(g_mTimeMenu);

	if(FileExists(sConfigFile))
	{
		g_iConfigState = 0;
		new SMCError:err = SMC_ParseFile(g_smcConfigParser, sConfigFile);
		if (err != SMCError_Okay)
		{
			decl String:sError[256];
			SMC_GetErrorString(err, sError, sizeof(sError));
			LogError("Could not parse file (file \"%s\"):", sConfigFile);
			LogError("Parser encountered error: %s", sError);
		}
	}
	else 
	{
		decl String:sError[PLATFORM_MAX_PATH+64];
		FormatEx(sError, sizeof(sError), "%sFATAL *** ERROR *** can not find %s", PREFIX, sConfigFile);
		LogError("FATAL *** ERROR *** can not find %s", sConfigFile);
		SetFailState(sError);
	}
}

public SMCResult:ReadConfig_NewSection(Handle:smc, const String:sName[], bool:opt_quotes)
{
	if(sName[0])
	{
		if(strcmp("Config", sName, false) == 0)
			g_iConfigState = CONFCONFIG;
		else if(strcmp("BanReasons", sName, false) == 0)
			g_iConfigState = CONFREASON;
		else if(strcmp("HackingReasons", sName, false) == 0)
			g_iConfigState = CONFHACKING;
		else if(strcmp("BanTime", sName, false) == 0)
			g_iConfigState = CONFTIME;
		else
			g_iConfigState = 0;
	}
	
	return SMCParse_Continue;
}

public SMCResult:ReadConfig_KeyValue(Handle:smc, const String:sKey[], const String:sValue[], bool:key_quotes, bool:value_quotes)
{
	if(!sKey[0] || !sValue[0])
		return SMCParse_Continue;

	switch(g_iConfigState)
	{
		case CONFCONFIG:
		{
			if(strcmp("DatabasePrefix", sKey, false) == 0) 
			{
				strcopy(g_sDatabasePrefix, sizeof(g_sDatabasePrefix), sValue);

				if(g_sDatabasePrefix[0] == '\0')
					g_sDatabasePrefix = "sb";
			}
			else if(strcmp("ServerID", sKey, false) == 0)
				g_iServerID = StringToInt(sValue);
			else if(strcmp("TimeFormat", sKey, false) == 0)
				strcopy(g_sFormatTime, sizeof(g_sFormatTime), sValue);
			else if(strcmp("MapClear", sKey, false) == 0)
			{
				if(StringToInt(sValue) == 0)
					g_bMapClear = false;
				else
					g_bMapClear = true;
			}
			else if(strcmp("MenuNewLine", sKey, false) == 0)
			{
				if(StringToInt(sValue) == 0)
					g_bMenuNewLine = false;
				else
					g_bMenuNewLine = true;
			}
			else if(strcmp("DelConPlayers", sKey, false) == 0)
			{
				if(StringToInt(sValue) == 0)
					g_bDelConPlayers = false;
				else
					g_bDelConPlayers = true;
			}
			else if(strcmp("MaxPlayers", sKey, false) == 0)
				g_iMaxStoredPlayers = StringToInt(sValue);
			else if(strcmp("MenuNast", sKey, false) == 0)
				g_iMenuItems = StringToInt(sValue);
		}
		case CONFREASON:
		{
			AddMenuItem(g_mReasonMenu, sKey, sValue);
		#if DEBUG
			LogToFile(g_sLogFile,"Loaded reason. key \"%s\", display_text \"%s\"", sKey, sValue);
		#endif
		}
		case CONFHACKING:
		{
			AddMenuItem(g_mHackingMenu, sKey, sValue);
		#if DEBUG
			LogToFile(g_sLogFile,"Loaded hacking reason. key \"%s\", display_text \"%s\"", sKey, sValue);
		#endif
		}
		case CONFTIME:
		{
			AddMenuItem(g_mTimeMenu, sKey, sValue);
		#if DEBUG
			LogToFile(g_sLogFile,"Loaded time. key \"%s\", display_text \"%s\"", sKey, sValue);
		#endif
		}
	}
	return SMCParse_Continue;
}

public SMCResult:ReadConfig_EndSection(Handle:smc)
{
	return SMCParse_Continue;
}

//получение айпи и порта сервера
InsertServerInfo()
{
	new iPieces[4], 
		iLongIP,
		Handle:cvarHostIp,
		Handle:cvarPort;	
	cvarHostIp = FindConVar("hostip");
	cvarPort = FindConVar("hostport");
	
	iLongIP = GetConVarInt(cvarHostIp);
	iPieces[0] = (iLongIP >> 24) & 0x000000FF;
	iPieces[1] = (iLongIP >> 16) & 0x000000FF;
	iPieces[2] = (iLongIP >> 8) & 0x000000FF;
	iPieces[3] = iLongIP & 0x000000FF;
	FormatEx(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d", iPieces[0], iPieces[1], iPieces[2], iPieces[3]);
	GetConVarString(cvarPort, g_sServerPort, sizeof(g_sServerPort));
}