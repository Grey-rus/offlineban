#if defined _offlineban_included
  #endinput
#endif
#define _offlineban_included

public SharedPlugin:__pl_offlineban = 
{
	name = "offlineban",
	file = "offlineban.smx",
#if defined REQUIRE_PLUGIN
    required = 1
#else
    required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_offlineban_SetNTVOptional()
{
	MarkNativeAsOptional("OffBanPlayer");
}
#endif


/*********************************************************
********RU******
* Добавить оффлайн бан.
*
* @param iClient	Клиент ид админа
* @param sSteamID	Стим айди
* @param sIp		Айпи
* @param sName		Ник
* @param iTime		Время (0 - навсегда) мин
* @param sReason	Причина (можно указать в виде "")
* @noreturn
********EN******
* Add offline ban.
*
* @param iClient	Admin Client ID
* @param sSteamID	SteamID
* @param sIp		IP
* @param sName		Nickname
* @param iTime		Time (0 - permanent) in minutes
* @param sReason	Reason (can leave a blank (""))
* @noreturn	
 *********************************************************/
native int OffBanPlayer(int iClient, char[] sSteamID, char[] sIp, char[] sName, int iTime, char[] sReason);