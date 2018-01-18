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
 * Off Ban Player from server
 *
 * @param iClient	Клиент ид админа кто банит
 * @param sSteamID	Стим айди кого банят
 * @param sIp		Айпи кого банят
 * @param sName		Ник кого банят
 * @param iTime		Время бана (0 - навсегда) мин
 * @param sReason	Причина
 * @noreturn		
 *********************************************************/
native int OffBanPlayer(int iClient, char[] sSteamID, char[] sIp, char[] sName, int iTime, char[] sReason);