#pragma semicolon 1
//#pragma tabsize 0

#include <sourcemod>
#include <offlineban>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <adminmenu>

#pragma newdecls required

#define MAX_STEAMID_LENGTH 32
#define MAX_IP_LENGTH 64

#define PREFIX "[Offline Ban]"
#define DEBUG 0 	//тестовый режим

char g_sTarget[MAXPLAYERS+1][4][125];
#define TNAME 0 	// Name
#define TIP 1		// ip
#define TSTEAMID 2 	// steam
#define TREASON 3 	// Reason

int g_iTarget[MAXPLAYERS+1][2];
#define TID 0  		// id
#define TTIME 1		// time

int	g_iServerID = -1,
	g_iMaxPlayers,
	g_iMenuItems,
	g_iSteamTyp,
	g_iSourcebansExt;

Database g_hSQLiteDB = null,
	g_hDatabase = null;

TopMenu g_tmAdminMenu;

Menu g_mReasonMenu,
	g_mHackingMenu,
	g_mTimeMenu;

char g_sServerIP[32], 
	g_sServerPort[8],
	g_sLogFile[256],
	g_sDatabasePrefix[10] = "sb",
	g_sSourcebansName[56] = "sourcebans",
	g_sFormatTime[56],
	g_sQuery[MAXPLAYERS+1][256];
	
bool g_bSourcebans = false,
	g_bNewConnect[MAXPLAYERS+1],
	g_bMapClear,
	g_bDelConPlayers,
	g_bMenuNewLine,
	g_bSayReason[MAXPLAYERS+1] = false;

SMCParser g_smcConfigParser;

int g_iConfigState;
#define	CONFCONFIG	1
#define CONFTIME	2
#define CONFREASON	3
#define	CONFHACKING	4

public Plugin myinfo = 
{
	name = "Offline Ban list",
	author = "Grey™ & R1KO",
	description = "For to sm 1.7",
	version = "2.5.1",
	url = "hlmod.ru Skype: wolf-1-ser"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("offlineban");
	CreateNative("OffBanPlayer", Native_OffBan);
}

public void OnPluginStart() 
{
	LoadTranslations("offlineban.phrases");
	
	RegAdminCmd("sm_offban_clear", CommandClearBan, ADMFLAG_ROOT, "Clear history");
	BuildPath(Path_SM, g_sLogFile, sizeof(g_sLogFile), "logs/offlineban.log");
	HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
	
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null))
		OnAdminMenuReady(topmenu);
	OffMenu();

	char sError[256];
	g_hSQLiteDB = SQLite_UseDatabase("offlineban", sError, sizeof(sError));
	if (g_hSQLiteDB == null)
		SetFailState("Database failure (%s)", sError);

	CreateOBTables();
	ReadConfig();
}

public void OnAllPluginsLoaded()
{
	if (g_iSourcebansExt)
		return;

	if (LibraryExists(g_sSourcebansName))
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

public void OnLibraryAdded(const char[] sName)
{
	if (!g_iSourcebansExt)
	{
		if (StrEqual(sName, g_sSourcebansName))
		{
			g_bSourcebans = true;
			ConectSourceBan();
		}
	}
	if (StrEqual(sName, "adminmenu"))
	{
		TopMenu topmenu;
		OnAdminMenuReady(topmenu);
	}
}

public void OnLibraryRemoved(const char[] sName)
{
	if (!g_iSourcebansExt)
	{
		if (StrEqual(sName, g_sSourcebansName))
		{
			g_bSourcebans = false;
			PrintToServer("%s Sourcebans OFF", PREFIX);
		}
	}
	if (StrEqual(sName, "adminmenu")) 
		g_tmAdminMenu = null;
}

void ConectSourceBan()
{
	PrintToServer("%s Sourcebans ON", PREFIX);
	char sError[256];
	g_hDatabase = SQL_Connect("sourcebans", false, sError, sizeof(sError));
	if (g_hDatabase == null && g_bSourcebans)
		SetFailState("Database failure (%s)", sError);
	
	InsertServerInfo();
}

public Action CommandClearBan(int iClient, int args)
{
	Clear_histories();

	ReplyToCommand(iClient, "%T",  "Clear history", iClient);
	
	return Plugin_Handled;
}

public void OnMapStart()
{ 
	ReadConfig();
	
	if(g_bMapClear) 
		Clear_histories();
}

void Clear_histories()
{
	char sQuery[64];
	FormatEx(sQuery, sizeof(sQuery), "DROP TABLE  `offlineban`");
	g_hSQLiteDB.Query(SQL_Callback_DeleteClients, sQuery);
}

public void SQL_Callback_DeleteClients(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (sError[0])
		LogToFile(g_sLogFile, "SQL_Callback_DeleteClients: %s", sError);
	else
		CreateOBTables();
}

public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
	if (g_bSayReason[iClient])
	{
		strcopy(g_sTarget[iClient][TREASON], sizeof(g_sTarget[][]), sArgs);
	#if DEBUG
		LogToFile(g_sLogFile,"Chat Reason: %s", sArgs);
	#endif
		PrintToChat2(iClient, "%T", "Own reason", iClient, sArgs);
		g_bSayReason[iClient] = false;
		CreateBanSB(iClient);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// удаление игроков вошедших в игру
public void OnClientPostAdminCheck(int iClient)
{
	if (!g_bDelConPlayers || !IsClientInGame(iClient) || IsFakeClient(iClient)) 
		return;

	if(g_bNewConnect[iClient])
		return;

	g_bNewConnect[iClient] = true;

	char sSteamID[MAX_STEAMID_LENGTH],
		 sQuery[256];
	
	switch(g_iSteamTyp)
	{
		case 1: GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID));
		case 2: GetClientAuthId(iClient, AuthId_Steam3, sSteamID, sizeof(sSteamID));
		case 3: GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	}
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `offlineban` WHERE `auth` = '%s'", sSteamID);
	g_hSQLiteDB.Query(SQL_Callback_DeleteClient, sQuery);
}

public void SQL_Callback_DeleteClient(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (sError[0])
		LogToFile(g_sLogFile, "SQL_Callback_DeleteClient: %s", sError);
}
 //зачисление в список игроков вышедших из игры
public void Event_PlayerDisconnect(Event eEvent, const char[] sEvName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(eEvent.GetInt("userid"));
	
	if (!iClient)
		return;

	if (!IsClientInGame(iClient) || IsFakeClient(iClient)) 
		return;

	if (GetUserAdmin(iClient) != INVALID_ADMIN_ID) 
		return;

	char sSteamID[MAX_STEAMID_LENGTH],
		 sName[MAX_NAME_LENGTH],
		 sEName[MAX_NAME_LENGTH*2+1],
		 sIP[MAX_IP_LENGTH];
		 
	g_bSayReason[iClient] = false;
	g_bNewConnect[iClient] = false;

	switch(g_iSteamTyp)
	{
		case 1: GetClientAuthId(iClient, AuthId_Steam2, sSteamID, sizeof(sSteamID));
		case 2: GetClientAuthId(iClient, AuthId_Steam3, sSteamID, sizeof(sSteamID));
		case 3: GetClientAuthId(iClient, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
	}
	GetClientName(iClient, sName, sizeof(sName));
	GetClientIP(iClient, sIP, sizeof(sIP));

	g_hSQLiteDB.Escape(sName, sEName, sizeof(sEName));

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "INSERT INTO `offlineban` (auth, ip, name, disc_time) VALUES \
										('%s', '%s', '%s', %i)", sSteamID, sIP, sEName, GetTime());
	g_hSQLiteDB.Query(SQL_Callback_AddClient, sQuery);

#if DEBUG
	char sTime[64];

	FormatTime(sTime, sizeof(sTime), g_sFormatTime, GetTime());
	LogToFile(g_sLogFile,"New: %s %s - %s ; %s.", sName, sSteamID, sIP, sTime);
#endif
}

public void SQL_Callback_AddClient(Database db, DBResultSet dbRs, const char[] sError, any iData)
{
	if (dbRs == null || sError[0])
		LogToFile(g_sLogFile, "SQL_Callback_AddClient: %s", sError);
}
//меню
void OffMenu()
{
	g_mReasonMenu = new Menu(MenuHandler_MenuReason);
	g_mReasonMenu.ExitBackButton = true;

	g_mHackingMenu = new Menu(MenuHandler_MenuHacking);
	g_mHackingMenu.ExitBackButton = true;

	g_mTimeMenu = new Menu(MenuHandler_MenuTime);
	g_mTimeMenu.ExitBackButton = true;
}

public void OnAdminMenuReady(Handle aTopMenu)
{
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	/* Block us from being called twice */
	if (topmenu == g_tmAdminMenu)
		return;

	/* Save the Handle */
	g_tmAdminMenu = topmenu;

	/* Find the "Player Commands" category */
	TopMenuObject categoryId = g_tmAdminMenu.FindCategory(ADMINMENU_PLAYERCOMMANDS);

	if (categoryId != INVALID_TOPMENUOBJECT)
		g_tmAdminMenu.AddItem("OfflineBans", AdminMenu_Ban, categoryId, "OfflineBans", ADMFLAG_BAN);
}

public void AdminMenu_Ban(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int iClient, char[] sBuffer, int maxlength)
{
	switch(action)
	{
		case TopMenuAction_DisplayOption: FormatEx(sBuffer, maxlength, "%T", "OfflineBansTitle", iClient);
		case TopMenuAction_SelectOption: ShowBanList(iClient);
	}
}
//меню выбора игрока
void ShowBanList(int iClient) 
{
	FormatEx(g_sQuery[iClient], sizeof(g_sQuery[]), "\
			SELECT `id`, `auth`, `name`, `disc_time` \
			FROM `offlineban` ORDER BY `id` DESC LIMIT %d;",
		g_iMaxPlayers);
	g_hSQLiteDB.Query(SendMenuCallback, g_sQuery[iClient], iClient, DBPrio_High);
}

public void SendMenuCallback(Database db, DBResultSet dbRs, const char[] sError, any iClient)
{
	if(dbRs == null)
	{
		LogError("Error loading offline ban (%s)", sError);
		return;
	}

	if(!IsClientInGame(iClient))
		return;
	
	Menu Mmenu = new Menu(MenuHandler_BanList);
	Mmenu.SetTitle("%T", "SelectPlayerTitle", iClient);
	char sTitle[128];

	if (dbRs.RowCount)
	{
		char sName[MAX_NAME_LENGTH],
			 sSteamID[MAX_STEAMID_LENGTH],
			 sID[12],
			 sTime[64];

		while(dbRs.FetchRow())
		{
			dbRs.FetchString(0, sID, sizeof(sID));
			dbRs.FetchString(1, sSteamID, sizeof(sSteamID));
			dbRs.FetchString(2, sName, sizeof(sName));
			FormatTime(sTime, sizeof(sTime), g_sFormatTime, dbRs.FetchInt(3));
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
			Mmenu.AddItem(sID, sTitle);
		#if DEBUG
			LogToFile(g_sLogFile,"Menu: %s, %s - %s", sID, sSteamID, sTitle);
		#endif
		}
	}
	else
	{
		FormatEx(sTitle, sizeof(sTitle), "%T", "No players history", iClient);
		Mmenu.AddItem("", sTitle, ITEMDRAW_DISABLED);	
	}
	
	Mmenu.ExitBackButton = true;
	Mmenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_BanList(Menu Mmenu, MenuAction mAction, int iClient, int iSlot) 
{
	switch(mAction)
	{
		case MenuAction_End: delete Mmenu;
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != null)
				g_tmAdminMenu.Display(iClient, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			char sID[12];
			Mmenu.GetItem(iSlot, sID, sizeof(sID));
			g_iTarget[iClient][TID] = StringToInt(sID);
			FormatEx(g_sQuery[iClient], sizeof(g_sQuery[]), "SELECT `auth`, `ip`, `name` FROM `offlineban` WHERE `id` = '%i'", g_iTarget[iClient][TID]);
			DBResultSet dbRs = SQL_Query(g_hSQLiteDB, g_sQuery[iClient]);

			if (g_hSQLiteDB == null || dbRs == null)
			{
				LogToFile(g_sLogFile, "Database, dbRs failure, Name");
				return;
			}
			
			if (dbRs.FetchRow())
			{
				dbRs.FetchString(0, g_sTarget[iClient][TSTEAMID], sizeof(g_sTarget[][]));
				dbRs.FetchString(1, g_sTarget[iClient][TIP], sizeof(g_sTarget[][]));
				dbRs.FetchString(2, g_sTarget[iClient][TNAME], sizeof(g_sTarget[][]));
			}
			else
			{
				PrintToChat2(iClient, "%T", "Failed to player", iClient, g_sTarget[iClient][TNAME]);
				return;
			}
			
			delete dbRs;

		#if DEBUG
			LogToFile(g_sLogFile,"Menu BanList: %i , %s ", g_iTarget[iClient][TID], g_sTarget[iClient][TNAME]);
		#endif

			ShowBanTimeMenu(iClient);
		}
	}
}

//меню выбора времени бана
void ShowBanTimeMenu(int iClient)
{
	char sTitle[128],
		 sBuffer[12];

	g_mTimeMenu.SetTitle("%T - %s", "SelectTimeTitle", iClient, g_sTarget[iClient][TNAME]);

	int iCount = g_mTimeMenu.ItemCount;
	for (int i = 0; i < iCount; i++)
	{
		g_mTimeMenu.GetItem(i, sBuffer, sizeof(sBuffer), _, sTitle, sizeof(sTitle));
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
				g_mTimeMenu.RemoveItem(i);
				g_mTimeMenu.InsertItem(i, sBuffer, sTitle);
			}
			else
			{
				g_mTimeMenu.RemoveItem(i);
				g_mTimeMenu.InsertItem(i, sBuffer, sTitle, ITEMDRAW_DISABLED);
			}
			break;
		}
	}

	g_mTimeMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_MenuTime(Menu Mmenu, MenuAction mAction, int iClient, int iSlot) 
{
	switch(mAction)
	{
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != null)
				ShowBanList(iClient);
		}
		case MenuAction_Select:
		{
			char sInfo[12];
			Mmenu.GetItem(iSlot, sInfo, sizeof(sInfo));
			g_iTarget[iClient][TTIME] = StringToInt(sInfo);
		#if DEBUG
			LogToFile(g_sLogFile,"Menu Time: %s", sInfo);
		#endif

			ShowBanReasonMenu(iClient);
		}
	}
}

//меню выбора причины бана
void ShowBanReasonMenu(int iClient)
{
	g_mReasonMenu.SetTitle("%T - %s", "SelectReasonTitle", iClient, g_sTarget[iClient][TNAME]);
	g_mReasonMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_MenuReason(Menu Mmenu, MenuAction mAction, int iClient, int iSlot) 
{
	switch(mAction)
	{
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != null)
				ShowBanTimeMenu(iClient);
		}
		case MenuAction_Select:
		{
			char sInfo[128];
			Mmenu.GetItem(iSlot, sInfo, sizeof(sInfo));
			if(StrEqual("Hacking", sInfo))
			{
				ShowBanHackingMenu(iClient);
				return;
			}
			if(StrEqual("Own Reason", sInfo))
			{
				PrintToChat2(iClient, "%T", "Say reason", iClient);
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

void ShowBanHackingMenu(int iClient)
{
	g_mHackingMenu.SetTitle("%T - %s", "SelectReasonTitle", iClient, g_sTarget[iClient][TNAME]);
	g_mHackingMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_MenuHacking(Menu Mmenu, MenuAction mAction, int iClient, int iSlot) 
{
	switch(mAction)
	{
		case MenuAction_Cancel:
		{
			if (iSlot == MenuCancel_ExitBack && g_tmAdminMenu != null)
				ShowBanReasonMenu(iClient);
		}
		case MenuAction_Select:
		{
			char sInfo[128];
			Mmenu.GetItem(iSlot, sInfo, sizeof(sInfo));
			strcopy(g_sTarget[iClient][TREASON], sizeof(sInfo), sInfo);
		#if DEBUG
			LogToFile(g_sLogFile,"Menu Hacking: %s", sInfo);
		#endif

			CreateBanSB(iClient);
		}
	}
}	

//занесение бана в бд
void CreateBanSB(int iClient)
{
	if(!g_bSourcebans)
	{
		CreateBan(iClient);
		return;
	}

	char sBanName[MAX_NAME_LENGTH*2+1],
		 sReason[200],
		 sQuery[1024],
		 sAdmin_SteamID[MAX_STEAMID_LENGTH],
		 sAdminIp[MAX_IP_LENGTH],
		 sQueryAdmin[156],
		 sServer[256];

	if (iClient)
	{
		switch(g_iSteamTyp)
		{
			case 1: GetClientAuthId(iClient, AuthId_Steam2, sAdmin_SteamID, sizeof(sAdmin_SteamID));
			case 2: GetClientAuthId(iClient, AuthId_Steam3, sAdmin_SteamID, sizeof(sAdmin_SteamID));
			case 3: GetClientAuthId(iClient, AuthId_SteamID64, sAdmin_SteamID, sizeof(sAdmin_SteamID));
		}
		GetClientIP(iClient, sAdminIp, sizeof(sAdminIp));
		FormatEx(sQueryAdmin, sizeof(sQueryAdmin), "IFNULL ((SELECT `aid` FROM %s_admins WHERE `authid` REGEXP '^STEAM_[0-9]:%s$' LIMIT 1), 0)", g_sDatabasePrefix, sAdmin_SteamID[8]);
	}
	else
	{
		strcopy(sAdmin_SteamID, sizeof(sAdmin_SteamID), "STEAM_ID_SERVER");
		strcopy(sAdminIp, sizeof(sAdminIp), g_sServerIP);
		strcopy(sQueryAdmin, sizeof(sQueryAdmin), "0");
	}

	int iTime = g_iTarget[iClient][TTIME]*60;

	g_hDatabase.Escape(g_sTarget[iClient][TNAME], sBanName, sizeof(sBanName));
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

	g_hDatabase.SetCharset("utf8");
	g_hDatabase.Query(VerifyInsert, sQuery, iClient, DBPrio_High);
#if DEBUG
	LogToFile(g_sLogFile,": %s", sQuery);
#endif
	LogAction(iClient, -1, "\"%L\" banned \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
							g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
}

//ответ занисения в бд бана(прошёл или нет)
public void VerifyInsert(Database db, DBResultSet dbRs, const char[] sError, any iClient)
{
	if (dbRs == null || sError[0])
	{
		LogToFile(g_sLogFile, "Verify Insert Query Failed: %s", sError);
		if (iClient > 0)
			PrintToChat2(iClient, "%T", "Failed to ban", iClient, g_sTarget[iClient][TNAME]);
	}
	else
	{
		char sQuery[125];
		if (iClient > 0)
			PrintToChat2(iClient, "%T", "Added to ban", iClient, g_sTarget[iClient][TNAME]);
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `offlineban` WHERE `id` = '%i';", g_iTarget[iClient][TID]);
		g_hSQLiteDB.Query(SQL_Callback_DeleteClient, sQuery);
	}
}

void CreateBan(int iClient)
{
	if(BanIdentity(g_sTarget[iClient][TSTEAMID], g_iTarget[iClient][TTIME], BANFLAG_AUTHID, g_sTarget[iClient][TREASON], ""))
		PrintToChat2(iClient, "%T", "Added to ban", iClient, g_sTarget[iClient][TNAME]);
	else
		PrintToChat2(iClient, "%T", "Failed to ban", iClient, g_sTarget[iClient][TNAME]);
	LogAction(iClient, -1, "\"%L\" banned \"%s (%s IP_%s)\" (minutes \"%d\") (reason \"%s\")", iClient, g_sTarget[iClient][TNAME], g_sTarget[iClient][TSTEAMID], 
							g_sTarget[iClient][TIP], g_iTarget[iClient][TTIME], g_sTarget[iClient][TREASON]);
}

void CreateOBTables()
{
	SQL_LockDatabase(g_hSQLiteDB);
	SQL_FastQuery(g_hSQLiteDB, "PRAGMA encoding = \"UTF-8\"");
	if(SQL_FastQuery(g_hSQLiteDB, "\
			CREATE TABLE IF NOT EXISTS `offlineban` (\
			`id` INTEGER PRIMARY KEY AUTOINCREMENT, \
			`auth` VARCHAR(32) UNIQUE ON CONFLICT REPLACE,\
			`ip` VARCHAR(24) NOT NULL, \
			`name` VARCHAR(64) DEFAULT 'unknown',\
			`disc_time` NUMERIC NOT NULL);"
			) == false)
	{
		char sError[256];
		SQL_GetError(g_hSQLiteDB, sError, sizeof(sError));
		SetFailState("%s Query CREATE TABLE failed! %s", PREFIX, sError);
	}
	SQL_UnlockDatabase(g_hSQLiteDB);
}

//получение значений конфига сб
void ReadConfig()
{
	if (!g_smcConfigParser)
		g_smcConfigParser = new SMCParser();
	
	g_smcConfigParser.OnEnterSection = NewSection;
	g_smcConfigParser.OnKeyValue = KeyValue;
	g_smcConfigParser.OnLeaveSection = EndSection;

	char sConfigFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/offban.cfg");

	if(g_mReasonMenu != null)
		g_mReasonMenu.RemoveAllItems();
	if(g_mHackingMenu != null)
		g_mHackingMenu.RemoveAllItems();
	if(g_mTimeMenu != null)
		g_mTimeMenu.RemoveAllItems();

	if(FileExists(sConfigFile))
	{
		g_iConfigState = 0;
	
		int iLine;
		SMCError err = g_smcConfigParser.ParseFile(sConfigFile, iLine);
		if (err != SMCError_Okay)
		{
			char sError[256];
			SMC_GetErrorString(err, sError, sizeof(sError));
			LogError("Could not parse file (line %d, file \"%s\"):", iLine, sConfigFile);
			LogError("Parser encountered error: %s", sError);
		}
	}
	else 
	{
		char sError[PLATFORM_MAX_PATH+64];
		FormatEx(sError, sizeof(sError), "%sFATAL *** ERROR *** can not find %s", PREFIX, sConfigFile);
		LogError("FATAL *** ERROR *** can not find %s", sConfigFile);
		SetFailState(sError);
	}
}

public SMCResult NewSection(SMCParser Smc, const char[] sName, bool bOpt_quotes)
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

public SMCResult KeyValue(SMCParser Smc, const char[] sKey, const char[] sValue, bool bKey_quotes, bool bValue_quotes)
{
	if(!sKey[0] || !sValue[0])
		return SMCParse_Continue;

	switch(g_iConfigState)
	{
		case CONFCONFIG:
		{
			if (strcmp("SourcebansExt", sKey, false) == 0)
			{
				g_iSourcebansExt = StringToInt(sValue);
				
				if (g_iSourcebansExt == 1)
				{
					g_bSourcebans = true;
					if (!g_hDatabase)
						ConectSourceBan();
				}
				else
				{
					g_bSourcebans = false;
					PrintToServer("%s Sourcebans OFF", PREFIX);
				}
			}
			else if(strcmp("SourcebansName", sKey, false) == 0) 
			{
				strcopy(g_sSourcebansName, sizeof(g_sSourcebansName), sValue);

				if(g_sSourcebansName[0] == '\0')
					g_sSourcebansName = "sourcebans";
			}
			else if(strcmp("DatabasePrefix", sKey, false) == 0) 
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
				g_iMaxPlayers = StringToInt(sValue);
			else if(strcmp("MenuNast", sKey, false) == 0)
				g_iMenuItems = StringToInt(sValue);
			else if(strcmp("SteamTyp", sKey, false) == 0)
				g_iSteamTyp = StringToInt(sValue);
		}
		case CONFREASON:
		{
			g_mReasonMenu.AddItem(sKey, sValue);
		#if DEBUG
			LogToFile(g_sLogFile,"Loaded reason. key \"%s\", display_text \"%s\"", sKey, sValue);
		#endif
		}
		case CONFHACKING:
		{
			g_mHackingMenu.AddItem(sKey, sValue);
		#if DEBUG
			LogToFile(g_sLogFile,"Loaded hacking reason. key \"%s\", display_text \"%s\"", sKey, sValue);
		#endif
		}
		case CONFTIME:
		{
			g_mTimeMenu.AddItem(sKey, sValue);
		#if DEBUG
			LogToFile(g_sLogFile,"Loaded time. key \"%s\", display_text \"%s\"", sKey, sValue);
		#endif
		}
	}
	return SMCParse_Continue;
}

public SMCResult EndSection(SMCParser Smc)
{
	return SMCParse_Continue;
}

//получение айпи и порта сервера
void InsertServerInfo()
{
	int iPieces[4], 
		iLongIP;
	ConVar cvarHostIp,
		cvarPort;	
	cvarHostIp = FindConVar("hostip");
	cvarPort = FindConVar("hostport");
	
	iLongIP = cvarHostIp.IntValue;
	iPieces[0] = (iLongIP >> 24) & 0x000000FF;
	iPieces[1] = (iLongIP >> 16) & 0x000000FF;
	iPieces[2] = (iLongIP >> 8) & 0x000000FF;
	iPieces[3] = iLongIP & 0x000000FF;
	FormatEx(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d", iPieces[0], iPieces[1], iPieces[2], iPieces[3]);
	cvarPort.GetString(g_sServerPort, sizeof(g_sServerPort));
}

void PrintToChat2(int iClient, const char[] sMesag, any ...)
{
	static const char sColorT[][] = {"#1",   "#2",   "#3",   "#4",   "#5",   "#6",   "#7",   "#8",   "#9",   "#10", "#OB",   "#OC",  "#OE"},
					  sColorC[][] = {"\x01", "\x02", "\x03", "\x04", "\x05", "\x06", "\x07", "\x08", "\x09", "\x10", "\x0B", "\x0C", "\x0E"};
	char sBufer[256];
	VFormat(sBufer, sizeof(sBufer), sMesag, 3);
	for(int i = 0; i < 13; i++)
		ReplaceString(sBufer, sizeof(sBufer), sColorT[i], sColorC[i]);

	if (GetUserMessageType() == UM_Protobuf)
		PrintToChat(iClient, " \x01%s %s", PREFIX, sBufer);
	else
		PrintToChat(iClient, "\x01%s %s", PREFIX, sBufer);
}

public int Native_OffBan(Handle plugin, int numParams)
{
	int iClient = GetNativeCell(1);
	GetNativeString(2, g_sTarget[iClient][TSTEAMID], sizeof(g_sTarget[][]));
	GetNativeString(3, g_sTarget[iClient][TIP], sizeof(g_sTarget[][]));
	GetNativeString(4, g_sTarget[iClient][TNAME], sizeof(g_sTarget[][]));
	g_iTarget[iClient][TTIME] = GetNativeCell(5);
	GetNativeString(6, g_sTarget[iClient][TREASON], sizeof(g_sTarget[][]));
	CreateBanSB(iClient);
}