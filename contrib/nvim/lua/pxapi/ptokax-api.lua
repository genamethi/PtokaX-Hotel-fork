--- @meta
--- PtokaX hub scripting API. Generated from scripting-interface.txt.
--- Regenerate with contrib/nvim/gen-api-defs.lua rather than editing.

--- @class BotInfo
--- @field sNick string
--- @field sMyINFO string
--- @field bIsOP boolean
--- @field sScriptName string

--- @class ScriptInfo
--- @field sName string
--- @field bEnabled boolean
--- @field iMemUsage integer

--- @class OpChatInfo
--- @field sNick string
--- @field sDescription string
--- @field sEmail string
--- @field bEnabled boolean

--- @class HubBotInfo
--- @field sNick string
--- @field sDescription string
--- @field sEmail string
--- @field bEnabled boolean
--- @field bUsedAsHubSecAlias boolean

--- Is called on script startup.
--- @type fun()
OnStartup = nil

--- Is called on script exit.
--- @type fun()
OnExit = nil

--- Default function called by timer on given interval.
--- @type fun(uTimerId: integer)
OnTimer = nil

--- Is called when user finish login sequence. When true is returned then hub don't send it to next scripts.
--- @type fun(tUser: User)
UserConnected = nil

--- Is called when user disconnect or was disconnected.
--- @type fun(tUser: User)
UserDisconnected = nil

--- Is called when reg finish login sequence. When true is returned then hub don't send it to next scripts.
--- @type fun(tUser: User)
RegConnected = nil

--- Is called when reg disconnect or was disconnected.
--- @type fun(tUser: User)
RegDisconnected = nil

--- Is called when operator finish login sequence. When true is returned then hub don't send it to next scripts.
--- @type fun(tUser: User)
OpConnected = nil

--- Is called when operator disconnect or was disconnected.
--- @type fun(tUser: User)
OpDisconnected = nil

--- Is called when error was found in script.
--- @type fun(sErrorMsg: string)
OnError = nil

--- Incoming supports from user.
--- @type fun(tUser: User, sData: string)
SupportsArrival = nil

--- Incoming chat message from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
ChatArrival = nil

--- Incoming key from user. It is called only when $Key is first command from client.
--- @type fun(tUser: User, sData: string)
KeyArrival = nil

--- Incoming validate nick from user.
--- @type fun(tUser: User, sData: string)
ValidateNickArrival = nil

--- Incoming password from user.
--- @type fun(tUser: User, sData: string)
PasswordArrival = nil

--- Incoming version from user.
--- @type fun(tUser: User, sData: string)
VersionArrival = nil

--- Incoming get nick list request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
GetNickListArrival = nil

--- Incoming user myinfo.
--- @type fun(tUser: User, sData: string)
MyINFOArrival = nil

--- Incoming get info request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
GetINFOArrival = nil

--- Incoming search request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
SearchArrival = nil

--- Incoming multi search request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
MultiSearchArrival = nil

--- Incoming private message from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
ToArrival = nil

--- Incoming active connection request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
ConnectToMeArrival = nil

--- Incoming multi connection request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
MultiConnectToMeArrival = nil

--- Incoming pasive connection request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
RevConnectToMeArrival = nil

--- Incoming search reply from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
SRArrival = nil

--- Incoming search reply from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
UDPSRArrival = nil

--- Incoming kick command from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
KickArrival = nil

--- Incoming redirect command from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
OpForceMoveArrival = nil

--- Incoming unknown command from user. If script return true hub don't process data (don't disconnect user).
--- @type fun(tUser: User, sData: string): boolean?
UnknownArrival = nil

--- Incoming hublist pinger request from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
BotINFOArrival = nil

--- Incoming close command from user. If script return true hub don't process data.
--- @type fun(tUser: User, sData: string): boolean?
CloseArrival = nil

--- @class CoreLib
--- Return PtokaX version.
--- @field Version string
--- Return PtokaX build number.
--- @field BuildNumber integer
--- Restart hub.
--- @field Restart fun()
--- Shutdown hub.
--- @field Shutdown fun()
--- Resume listening thread(s) if they were suspended.
--- @field ResumeAccepts fun()
--- Stop listening thread(s). Hub looks in this time like it is not running.
--- @field SuspendAccepts fun()
--- @overload fun(nTime: number)
--- Chars $| and space not allowed in nick. $ and | not allowed in Description and Email, max length 64 chars per string. Return nil when failed, true when success.
--- @field RegBot fun(sBotName: string, sDescription: string, sEmail: string, bHaveKey: boolean): boolean?
--- Return nil when failed, true when success.
--- @field UnregBot fun(sBotName: string): boolean?
--- Return table with all bots registered by scripts as tables with sNick, sMyINFO, bIsOP and sScriptName.
--- @field GetBots fun(): BotInfo[]
--- Return actual users peak.
--- @field GetActualUsersPeak fun(): integer
--- Return max users peak.
--- @field GetMaxUsersPeak fun(): integer
--- Return total hub share size in bytes.
--- @field GetCurrentSharedSize fun(): integer
--- Return IP if is available, or nil when not.
--- @field GetHubIP fun(): string?
--- Return table with one or more IP addreses or nil when no address is available.
--- @field GetHubIPs fun(): string[]?
--- Return actual Hub-Security alias.
--- @field GetHubSecAlias fun(): string
--- Return PtokaX path.
--- @field GetPtokaXPath fun(): string
--- Return hub users count.
--- @field GetUsersCount fun(): integer
--- Return hub uptime in seconds.
--- @field GetUpTime fun(): integer
--- Return table with all logged user tables without operator status.
--- @field GetOnlineNonOps fun(): User[]
--- @overload fun(bAllData: boolean): User[]
--- Return table with all logged user tables with operator status.
--- @field GetOnlineOps fun(): User[]
--- @overload fun(bAllData: boolean): User[]
--- Return table with all logged and registered (profile > -1) user tables.
--- @field GetOnlineRegs fun(): User[]
--- @overload fun(bAllData: boolean): User[]
--- Return table with all logged user tables.
--- @field GetOnlineUsers fun(): User[]
--- @overload fun(bAllData: boolean): User[]
--- @overload fun(iProfileNumber: integer): User[]
--- @overload fun(iProfileNumber: integer, bAllData: boolean): User[]
--- Return online user as user table.
--- @field GetUser fun(sNick: string): User?
--- @overload fun(sNick: string, bAllData: boolean): User?
--- Add or update all user data in user table. Return nil when failed (user is not online) or true when sucess.
--- @field GetUserAllData fun(tUser: User): boolean?
--- Add or update value of given id in user table. Return nil when failed (user is not online) or true when sucess.
--- @field GetUserData fun(tUser: User, iValueId: integer): boolean?
--- Return value of wanted iValueId or nil when failed (user is not online).
--- @field GetUserValue fun(tUser: User, iValueId: integer): any
--- Return online users from given ip as table with user tables or nil when no user with that IP is found or invalid IP is given.
--- @field GetUsers fun(sIP: string): User[]?
--- @overload fun(sIP: string, bAllData: boolean): User[]?
--- Disconnect user with given nick. Return nil when failed, true when success.
--- @field Disconnect fun(sNick: string): boolean?
--- @overload fun(tUser: User): boolean?
--- Kick user. Max KickerNick length 64 chars, max Reason length 128000 chars. Return nil when failed, true when success.
--- @field Kick fun(tUser: User, sKickerNick: string, sReason: string): boolean?
--- Redirect user to given address with given reason. Max Address length 1024 chars. Max Reason length 128000 chars. Return nil when failed, true when success.
--- @field Redirect fun(tUser: User, sAddress: string, sReason: string): boolean?
--- Warn user on flood. Return nil when failed, true when success.
--- @field DefloodWarn fun(tUser: User): boolean?
--- Send data to all users. Max sData length 128000 chars. When data don't contains | on end, will be automatically added.
--- @field SendToAll fun(sData: string)
--- Send data to user with given nick. Max sData length 128000 chars. When data don't contains | on end, will be automatically added.
--- @field SendToNick fun(sNick: string, sData: string)
--- Send data as private message in OpChat. Max sData length 128000 chars. If OpChat is not enabled then nothing is sent.
--- @field SendToOpChat fun(sData: string)
--- Send data to operators. Max sData length 128000 chars. When data don't contains | on end, will be automatically added.
--- @field SendToOps fun(sData: string)
--- Send data to users with given profile. Max sData length 128000 chars. When data don't contains | on end, will be automatically added.
--- @field SendToProfile fun(iProfileNumber: integer, sData: string)
--- Send data to user. Max Data length 128000 chars. When data don't contains | on end, will be automatically added.
--- @field SendToUser fun(tUser: User, sData: string)
--- Send data as private message to all users. Max FromNick length 64 chars, max Data length 128000 chars.
--- @field SendPmToAll fun(sFromNick: string, sData: string)
--- Send data as private message to user with given nick. Max FromNick length 64 chars, max Data length 128000 chars.
--- @field SendPmToNick fun(sToNick: string, sFromNick: string, sData: string)
--- Send data to operators. Max FromNick length 64 chars, max Data length 128000 chars.
--- @field SendPmToOps fun(sFromNick: string, sData: string)
--- Send data as private message to users with given profile. Max FromNick length 64 chars, max Data length 128000 chars.
--- @field SendPmToProfile fun(iProfileNumber: integer, sFromNick: string, sData: string)
--- Send private message to user. Max FromNick length 64 chars, max Data length 128000 chars.
--- @field SendPmToUser fun(tUser: User, sFromNick: string, sData: string)

--- @type CoreLib
Core = {}

--- @class SetManLib
--- Save settings.
--- @field Save fun()
--- @field GetMOTD fun(): string?
--- | is not allowed.
--- @field SetMOTD fun(sString: string)
--- true or nil.
--- @field GetBool fun(iBoolId: integer): boolean?
--- @field SetBool fun(iBoolId: integer, bBoolean: boolean)
--- @field GetNumber fun(iNumberId: integer): integer?
--- @field SetNumber fun(iNumberId: integer, iNumber: integer)
--- String or nil.
--- @field GetString fun(iStringId: integer): string?
--- @field SetString fun(iStringId: integer, sString: string)
--- Return min share in bytes.
--- @field GetMinShare fun(): integer
--- @field SetMinShare fun(iShareInBytes: integer)
--- @overload fun(iMinShare: integer, iShareUnits: integer)
--- Return max share in bytes.
--- @field GetMaxShare fun(): integer
--- @field SetMaxShare fun(iShareInBytes: integer)
--- @overload fun(iMaxShare: integer, iShareUnits: integer)
--- @field SetHubSlotRatio fun(iHubs: integer, iSlots: integer)
--- Return table with sNick, sDescription, sEmail, bEnabled.
--- @field GetOpChat fun(): OpChatInfo
--- Max length of string is 64 chars !!! In nick is not allowed $|<>:?*"/\ and space. In Description and Email is not allowed $ and |. Return nil when failed, true when success.
--- @field SetOpChat fun(bEnabled: boolean, sNewOpChatName: string, sNewDescription: string, sNewEmail: string): boolean?
--- Return table with sNick, sDescription, sEmail, bEnabled, bUsedAsHubSecAlias.
--- @field GetHubBot fun(): HubBotInfo
--- Max length of string is 64 chars !!! In nick is not allowed $|<>:?*"/\ and space. In Description and Email is not allowed $ and |. Return nil when failed, true when success.
--- @field SetHubBot fun(bEnabled: boolean, sNewHubBotName: string, sNewDescription: string, sNewEmail: string, bUseAsHubSecAlias: boolean): boolean?

--- @type SetManLib
SetMan = {}

--- @class RegManLib
--- Save registered users.
--- @field Save fun()
--- Return table with all registered users with given profile as registered user tables.
--- @field GetRegsByProfile fun(iProfileNumber: integer): RegisteredUser[]
--- Return table with all registered users without operator status as registered user tables.
--- @field GetNonOps fun(): RegisteredUser[]
--- Return table with all registered users with operator status as registered user tables.
--- @field GetOps fun(): RegisteredUser[]
--- Return registered user with given nick as registered user table or nil when reg with this nick not exist.
--- @field GetReg fun(sNick: string): RegisteredUser?
--- Return table with all registered users as registered user tables.
--- @field GetRegs fun(): RegisteredUser[]
--- Chars $| and space not allowed in nick. Max nick length 64 chars. Hub will ask user for password and after password is received then user will be registered. Return nil when failed, true if success.
--- @field AddReg fun(sNick: string, iProfileNumber: integer): boolean?
--- @overload fun(sNick: string, sPass: string, iProfileNumber: integer): boolean?
--- Return nil when failed, true if success.
--- @field DelReg fun(sNick: string): boolean?
--- Return nil when failed, true if success. When you don't want to change password then use nil instead of string as second param.
--- @field ChangeReg fun(sNick: string, sPass: string, iProfileNumber: integer): boolean?
--- Clear advanced password protection bad password count for given nick. Return nil when failed, true if success.
--- @field ClrRegBadPass fun(sNick: string): boolean?

--- @type RegManLib
RegMan = {}

--- @class BanManLib
--- Save bans.
--- @field Save fun()
--- Return table with ban tables.
--- @field GetBans fun(): Ban[]
--- Return table with ban tables.
--- @field GetTempBans fun(): Ban[]
--- Return table with ban tables.
--- @field GetPermBans fun(): Ban[]
--- Return ban table with ban for given nick or nil when not exist. Return table with ban table(s) with ban(s) for given ip or nil when not exist.
--- @field GetBan fun(sNick: string): Ban|Ban[]|nil
--- Return ban table with permban for given nick or nil when not exist. Return table with ban table(s) with permban(s) for given ip or nil when not exist.
--- @field GetPermBan fun(sNick: string): Ban|Ban[]|nil
--- Return ban table with tempban for given nick or nil when not exist. Return table with ban table(s) with tempban(s) for given ip or nil when not exist.
--- @field GetTempBan fun(sNick: string): Ban|Ban[]|nil
--- Return table with range ban tables.
--- @field GetRangeBans fun(): RangeBan[]
--- Return table with range ban tables.
--- @field GetTempRangeBans fun(): RangeBan[]
--- Return table with range ban tables.
--- @field GetPermRangeBans fun(): RangeBan[]
--- Return range ban table with rangeban for given range or nil when not exist.
--- @field GetRangeBan fun(sIPFrom: string, sIPTo: string): RangeBan?
--- Return range ban table with rangepermban for given range or nil when not exist.
--- @field GetRangePermBan fun(sIPFrom: string, sIPTo: string): RangeBan?
--- Return range ban table with rangetempban for given range or nil when not exist.
--- @field GetRangeTempBan fun(sIPFrom: string, sIPTo: string): RangeBan?
--- Unban ban with given nick or ip. Return nil when failed, true if success.
--- @field Unban fun(sNick: string): boolean?
--- Unban permban with given nick or ip. Return nil when failed, true if success.
--- @field UnbanPerm fun(sNick: string): boolean?
--- Unban tempban with given nick or ip. Return nil when failed, true if success.
--- @field UnbanTemp fun(sNick: string): boolean?
--- Unban all bans with given ip.
--- @field UnbanAll fun(sIP: string)
--- Unban all permbans with given ip.
--- @field UnbanPermAll fun(sIP: string)
--- Unban all tempbans with given ip.
--- @field UnbanTempAll fun(sIP: string)
--- Unban range ban with given range. Return nil when failed, true if success.
--- @field RangeUnban fun(sIPFrom: string, sIPTo: string): boolean?
--- Unban permanent range ban with given range. Return nil when failed, true if success.
--- @field RangeUnbanPerm fun(sIPFrom: string, sIPTo: string): boolean?
--- Unban temporary range ban with given range. Return nil when failed, true if success.
--- @field RangeUnbanTemp fun(sIPFrom: string, sIPTo: string): boolean?
--- Clear all bans.
--- @field ClearBans fun()
--- Clear all perm bans.
--- @field ClearPermBans fun()
--- Clear all temp bans.
--- @field ClearTempBans fun()
--- Clear all range bans.
--- @field ClearRangeBans fun()
--- Clear all range perm bans.
--- @field ClearRangePermBans fun()
--- Clear all range temp bans.
--- @field ClearRangeTempBans fun()
--- Perm ban user. Return nil when failed, true if success.
--- @field Ban fun(tUser: User, sReason: string, sBy: string, bFull: boolean): boolean?
--- Perm ban given ip. Return nil when failed, true if success.
--- @field BanIP fun(sIP: string, sReason: string, sBy: string, bFull: boolean): boolean?
--- Perm ban given nick. Return nil when failed, true if success.
--- @field BanNick fun(sNick: string, sReason: string, sBy: string): boolean?
--- Temp ban user. iTime is in minutes (0 = default tempban time from settings) ! Return nil when failed, true if success.
--- @field TempBan fun(tUser: User, iTime: integer, sReason: string, sBy: string, bFull: boolean): boolean?
--- Temp ban given ip. iTime is in minutes (0 = default tempban time from settings) ! Return nil when failed, true if success.
--- @field TempBanIP fun(sIP: string, iTime: integer, sReason: string, sBy: string, bFull: boolean): boolean?
--- Temp ban given nick. iTime is in minutes (0 = default tempban time from settings) ! Return nil when failed, true if success.
--- @field TempBanNick fun(sNick: string, iTime: integer, sReason: string, sBy: string): boolean?
--- Range perm ban given range. Return nil when failed, true if success.
--- @field RangeBan fun(sIPFrom: string, sIPTo: string, sReason: string, sBy: string, bFull: boolean): boolean?
--- Range temp ban given range. iTime is in minutes (0 = default tempban time from settings) ! Return nil when failed, true if success.
--- @field RangeTempBan fun(sIPFrom: string, sIPTo: string, iTime: integer, sReason: string, sBy: string, bFull: boolean): boolean?

--- @type BanManLib
BanMan = {}

--- @class ProfManLib
--- Add profile to profilemanager, return iProfileNumber if success or nil when profile already exist.
--- @field AddProfile fun(sProfileName: string): integer?
--- Remove profile from profilemanager, return true if success or nil when profile not exist or is in use.
--- @field RemoveProfile fun(sProfileName: string): boolean?
--- Move profile down. Return nil when failed, true if success.
--- @field MoveDown fun(iProfileNumber: integer): boolean?
--- Move profile up. Return nil when failed, true if success.
--- @field MoveUp fun(iProfileNumber: integer): boolean?
--- Return profile as profile table or nil if not exist.
--- @field GetProfile fun(sProfileName: string): Profile?
--- Return table with profiles as profile tables.
--- @field GetProfiles fun(): Profile[]
--- Return true if permission is true, or nil.
--- @field GetProfilePermission fun(iProfileNumber: integer, iPermissionId: integer): boolean?
--- Return table with profile permissions.
--- @field GetProfilePermissions fun(iProfileNumber: integer): ProfilePermissions
--- Change profile name, return true if success or nil if profile not exist.
--- @field SetProfileName fun(iProfileNumber: integer, sProfileName: string): boolean?
--- Change profile permission, return true if success or nil if profile not exist.
--- @field SetProfilePermission fun(iProfileNumber: integer, iPermissionId: integer, bBoolean: boolean): boolean?
--- Save profiles.
--- @field Save fun()

--- @type ProfManLib
ProfMan = {}

--- @class TmrManLib
--- Add new timer for script. iTimerInterval is in ms. Return nil when failed or uTimerId when success.
--- @field AddTimer fun(iTimerInterval: integer): integer?
--- @overload fun(iTimerInterval: integer, fFunction: function): integer?
--- @overload fun(iTimerInterval: integer, sFunctionName: string): integer?
--- Remove timer with given ID from script.
--- @field RemoveTimer fun(uTimerId: integer)

--- @type TmrManLib
TmrMan = {}

--- @class UDPDbgLib
--- Register to receiving data to PtokaX UDP Debug receiver, bAllData false means to receive only data from this script. Return nil when failed or true when success.
--- @field Reg fun(sIp: string, iPort: integer, bAllData: boolean): boolean?
--- Remove from receiving data.
--- @field Unreg fun()
--- Send data to udp debug. If script is registered then only to this reg, else to all. Return nil when failed or true when success.
--- @field Send fun(sData: string): boolean?

--- @type UDPDbgLib
UDPDbg = {}

--- @class ScriptManLib
--- Return script table with sName, bEnabled, iMemUsage.
--- @field GetScript fun(): ScriptInfo
--- Return table with scripts as tables with sName, bEnabled, iMemUsage.
--- @field GetScripts fun(): ScriptInfo[]
--- Move script up in script order. Return nil when failed, true if success.
--- @field MoveUp fun(sScriptName: string): boolean?
--- Move script down in script order. Return nil when failed, true if success.
--- @field MoveDown fun(sScriptName: string): boolean?
--- Start script with given name. Return nil when failed, true if success.
--- @field StartScript fun(sScriptName: string): boolean?
--- Restart script with given name. Return nil when failed, true if success.
--- @field RestartScript fun(sScriptName: string): boolean?
--- Stop script with given name. Return nil when failed, true if success.
--- @field StopScript fun(sScriptName: string): boolean?
--- Restart scripting interface.
--- @field Restart fun()
--- Refresh script list.
--- @field Refresh fun()

--- @type ScriptManLib
ScriptMan = {}

--- @class IP2CountryLib
--- Return country code of given IP or nil when IP is not valid.
--- @field GetCountryCode fun(sIP: string): string?
--- Return country name of given IP or nil when IP is not valid.
--- @field GetCountryName fun(sIP: string): string?
--- @overload fun(tUser: User): string?
--- Reload (update) database from database files.
--- @field Reload fun()

--- @type IP2CountryLib
IP2Country = {}

--- @class User
--- @field sNick string User nick.
--- @field sIP string User ip address.
--- @field uptr lightuserdata Memory address to original user data structure, for internal PtokaX use. Don't modify it, else functions with user table parameter will not work.
--- @field iProfile integer User profile.
--- @field sMode string? User mode (from tag) or nil when user don't have tag or mode in tag.
--- @field sMyInfoString string? User MYINFO string or nil when user don't send MyINFO yet.
--- @field sDescription string? User description or nil when user don't have description.
--- @field sTag string? User tag or nil when user don't have tag.
--- @field sConnection string? User connection or nil when user don't have connection.
--- @field sEmail string? User email or nil when user don't have email.
--- @field sClient string? User client (from tag) or nil when user don't have tag.
--- @field sClientVersion string? User client version (from tag) or nil when user don't have tag.
--- @field sVersion string? User version (from $Version) or nil when user don't send Version.
--- @field sCountryCode string? User country code or nil when ip-to-country database is not loaded.
--- @field bConnected boolean User is added in hub (visible for other users, added is after User/Reg/OpConnected).
--- @field bActive boolean? true when user is active (from tag or is sending active commands) or nil when is not active.
--- @field bOperator boolean User have operator status.
--- @field bUserCommand boolean User support UserCommands protocol extension.
--- @field bQuickList boolean User support QuickList protocol extension.
--- @field bSuspiciousTag boolean User have suspicious tag.
--- @field iShareSize integer User share size.
--- @field iHubs integer User hubs count (from tag).
--- @field iNormalHubs integer? User hubs without registration count (from tag) or nil if user don't have tag or have old-style (only H:x) tag.
--- @field iRegHubs integer? User hubs with registration count (from tag) or nil if user don't have tag or have old-style (only H:x) tag.
--- @field iOpHubs integer? User hubs with operator status (from tag) or nil if user don't have tag or have old-style (only H:x) tag.
--- @field iSlots integer User slots count (from tag).
--- @field iLlimit integer User L or B limit (from tag).
--- @field iDefloodWarns integer User deflood warns count.
--- @field iMagicByte integer Number of ascii char after connection in myinfo.
--- @field iLoginTime integer User login time in seconds from 1.1.1970
--- @field tIPs string[] Table with one or more user IP addresses.
--- @class RegisteredUser
--- @field sNick string Reg user nick.
--- @field sPassword string? Reg user password or nil when password hashing is enabled.
--- @field iProfile integer Reg user profile.
--- @class Ban
--- @field sIP string? ip or nil when ban don't have ip.
--- @field sNick string? nick or nil when ban don't have nick.
--- @field sReason string? reason or nil when ban don't have reason.
--- @field sBy string? nick of operator who create ban or or nil when ban don't have it.
--- @field iExpireTime integer? Seconds from 1.1.1970 or nil when ban is perm ban.
--- @field bIpBan boolean? true or nil.
--- @field bNickBan boolean? true or nil.
--- @field bFullIpBan boolean? true or nil.
--- @class RangeBan
--- @field sReason string? reason or nil when ban don't have reason.
--- @field sBy string? nick of operator who create ban or or nil when ban don't have it.
--- @field iExpireTime integer? Seconds from 1.1.1970 or nil when ban is perm ban.
--- @field bFullIpBan boolean? true or nil.
--- @class Profile
--- @class ProfilePermissions
--- @field bIsOP boolean User have key / is OP
--- @field bNoDefloodGetNickList boolean No GetNickList Deflood
--- @field bNoDefloodNMyINFO boolean No MyINFO Deflood
--- @field bNoDefloodSearch boolean No Search Deflood
--- @field bNoDefloodPM boolean No PM Deflood
--- @field bNoDefloodMainChat boolean No Main Chat Deflood
--- @field bMassMsg boolean Mass Message
--- @field bTopic boolean Topic
--- @field bTempBan boolean TempBan
--- @field bTempUnban boolean TempUnban
--- @field bRefreshTxt boolean Reload text files
--- @field bNoTagCheck boolean No Tag check
--- @field bDelRegUser boolean DelRegUser
--- @field bAddRegUser boolean AddRegUser
--- @field bNoChatLimits boolean No ChatLimits
--- @field bNoMaxHubCheck boolean No MaxHubs Check
--- @field bNoSlotHubRatio boolean No Slot/Hub ratio check
--- @field bNoSlotCheck boolean No SlotCheck
--- @field bNoShareLimit boolean No ShareLimit
--- @field bClrPermBan boolean Clear PermBan
--- @field bClrTempBan boolean Clear TempBan
--- @field bGetInfo boolean GetInfo
--- @field bGetBans boolean Get Bans
--- @field bRestartScripts boolean Start/Stop/Restart script(s)
--- @field bRestartHub boolean Restart hub
--- @field bTempOP boolean TempOP
--- @field bGag boolean Gag, Ungag
--- @field bRedirect boolean Redirect
--- @field bBan boolean Ban
--- @field bUnban boolean Unban
--- @field bKick boolean Kick
--- @field bDrop boolean Drop
--- @field bEnterFullHub boolean Enter full hub
--- @field bEnterIfIPBan boolean Enter hub if IP banned
--- @field bAllowedOPChat boolean Allowed for OpChat
--- @field bSendFullMyinfos boolean Send full myinfos
--- @field bSendAllUserIP boolean Send all users IP
--- @field bRangeBan boolean Range ban
--- @field bRangeUnban boolean Range unban
--- @field bRangeTempBan boolean Range temp ban
--- @field bRangeTempUnban boolean Range temp unban
--- @field bGetRangeBans boolean Get range perm bans
--- @field bClearRangePermBans boolean Clear range perm bans
--- @field bClearRangeTempBans boolean Clear range temp bans
--- @field bNoIpCheck boolean No IP checking in connection and search request.
--- @field bClose boolean Close
--- @field bNoSearchLimits boolean No search length limits.
--- @field bNoDefloodCTM boolean No ConnectToMe deflood.
--- @field bNoDefloodRCTM boolean No RevConnectToMe deflood.
--- @field bNoDefloodSR boolean No search reply deflood.
--- @field bNoDefloodRecv boolean No received data deflood.
--- @field bNoChatInterval boolean No chat interval.
--- @field bNoPMInterval boolean No private message interval.
--- @field bNoSearchInterval boolean No search interval.
--- @field bNoMaxUsersSameIP boolean No maximum users from same IP.
--- @field bNoReConnTime boolean No reconnect time.
--- @class SetMantBooleans
--- @field AntiMoGlo integer Anti MoGlo description
--- @field AutoStart integer Hub autostart
--- @field RedirectAll integer Redirect all connecting users
--- @field RedirectWhenHubFull integer Redirect users when hub is full
--- @field AutoReg integer Automatically register to hublist
--- @field RegOnly integer Hub for registered users only
--- @field RegOnlyRedir integer Redirect non
--- @field ShareLimitRedir integer Redirect user when he's don't have share limit
--- @field SlotLimitRedir integer Redirect user when he's don't have slot limit
--- @field HubSlotRatioRedir integer Redirect user when he's don't have hub/slot ratio limit
--- @field MaxHubsLimitRedir integer Redirect user when he's don't have max hubs limit
--- @field ModeToMyInfo integer Add user mode to MyINFO command.
--- @field ModeToDescription integer Add user mode to description.
--- @field StripDescription integer Strip user description.
--- @field StripTag integer Strip user description tag.
--- @field StripConnection integer Strip user connection.
--- @field StripEmail integer Strip user email
--- @field RegBot integer Register hub bot on hub.
--- @field UseBotAsHubSec integer Use hub bot nick instead of Hub
--- @field RegOpChat integer Register Opchat bot on hub.
--- @field TempBanRedir integer Redirect user when is temp banned.
--- @field PermBanRedir integer Redirect user when is perm banned.
--- @field EnableScripting integer Enable scripting interface.
--- @field KeepSlowUsers integer Keep slow clients.
--- @field CheckNewReleases integer Automatically check for new PtokaX releases on startup
--- @field EnableTrayIcon integer Enable tray icon.
--- @field StartMinimized integer Start minimized.
--- @field FilterKickMessages integer Filter kick messages.
--- @field SendKickMessagesToOps integer Send kick messages to OPs.
--- @field SendStatusMessages integer Send status messages to OPs.
--- @field SendStatusMessagesAsPm integer Send status messages as private messages.
--- @field EnableTextFiles integer Enable text files.
--- @field SendTextFilesAsPm integer Send text files as private messages.
--- @field StopScriptOnError integer Stop script on error.
--- @field SendMotdAsPm integer Send MOTD as private message.
--- @field DefloodReport integer Report deflood actions.
--- @field ReplyToHubCommandsAsPm integer Reply to hub commands with private messages.
--- @field DisableMotd integer Disable MOTD.
--- @field DontAllowPingers integer Don't allow hublist pingers.
--- @field ReportPingers integer Report hublist pingers.
--- @field Report3xBadPass integer Report 3x bad password.
--- @field AdvancedPassProtection integer Advanced password protection.
--- @field ListenOnlySingleIp integer Listen only on single IP.
--- @field ResolveToIp integer Resolve hostname to IP.
--- @field NickLimitRedir integer Redir user when he's don't have nick in length limits.
--- @field BanMsgShowIp integer Send ip in ban message.
--- @field BanMsgShowRange integer Send range in ban message.
--- @field BanMsgShowNick integer Send nick in ban message.
--- @field BanMsgShowReason integer Send reason in ban message.
--- @field BanMsgShowBy integer Send who create ban in ban message.
--- @field ReportSuspiciousTag integer Report suspicious tag to OPs.
--- @field LogScriptErrors integer Save script errors to log.
--- @field DisallowBadSupports integer Disallow clients sending buggy supports.
--- @field HashPasswords integer Hash registered users passwords.
--- @field EnableDatabase integer Enable/Disable database support.

--- @type SetMantBooleans
SetMan.tBooleans = {}

--- @class SetMantNumbers
--- @field MaxUsers integer Max users limit
--- @field MinShareLimit integer Min share limit. Max 9999.
--- @field MinShareUnits integer Min share units. 0 = B, 1 = kB, 2 = MB, 3 = GB, 4 = TB. Max 4.
--- @field MaxShareLimit integer Max share limit. Max 9999.
--- @field MaxShareUnits integer Max share units. 0 = B, 1 = kB, 2 = MB, 3 = GB, 4 = TB. Max 4.
--- @field MinSlotsLimit integer Min slots limit.
--- @field MaxSlotsLimit integer Max slots limit.
--- @field HubSlotRatioHubs integer Hubs for hub/slot ratio.
--- @field HubSlotRatioSlots integer Slots for hub/slot ratio.
--- @field MaxHubsLimit integer Max hubs limit.
--- @field NoTagOption integer No tag option. 0 = accept, 1 = reject, 2 = redirect. Max 2.
--- @field LongMyinfoOption integer Send full MyINFO to... 0 = to all, 1 = to profile, 2 = to none. Max 2.
--- @field MaxChatLen integer Max chat length limit.
--- @field MaxChatLines integer Max chat lines limit.
--- @field MaxPmLen integer Max private message length limit.
--- @field MaxPmLines integer Max private message lines limit.
--- @field DefaultTempBanTime integer Default tempban time. Must be higher than 0.
--- @field MaxPasiveSr integer Max passive search replys limit.
--- @field MyInfoDelay integer Time before new MyINFO from user is accepted for broadcast.
--- @field MainChatMessages integer Main chat deflood messages count. Higher than 0, max 29999.
--- @field MainChatTime integer Main chat deflood time. Higher than 0, max 29999.
--- @field MainChatAction integer Main chat deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SameMainChatMessages integer Same main chat deflood messages count. Higher than 0, max 29999.
--- @field SameMainChatTime integer Same main chat deflood time. Higher than 0, max 29999.
--- @field SameMainChatAction integer Same main chat deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SameMultiMainChatMessages integer Same multiline main chat deflood messages count. Min 2, max 999.
--- @field SameMultiMainChatLines integer Same multiline main chat deflood lines. Min 2, max 999.
--- @field SameMultiMainChatAction integer Same multiline main chat deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field PmMessages integer Private message deflood messages count. Higher than 0, max 29999.
--- @field PmTime integer Private message deflood time. Higher than 0, max 29999.
--- @field PmAction integer Private message deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SamePmMessages integer Same private message deflood messages count. Higher than 0, max 29999.
--- @field SamePmTime integer Same private message deflood time. Higher than 0, max 29999.
--- @field SamePmAction integer Same private message deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SameMultiPmMessages integer Same multiline private message deflood messages count. Min 2, max 999.
--- @field SameMultiPmLines integer Same multiline private message deflood lines. Min 2, max 999.
--- @field SameMultiPmAction integer Same multiline private message action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SearchMessages integer Search deflood messages count. Higher than 0, max 29999.
--- @field SearchTime integer Search deflood time. Higher than 0, max 29999.
--- @field SearchAction integer Search deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SameSearchMessages integer Same search deflood messages count. Higher than 0, max 29999.
--- @field SameSearchTime integer Same search deflood time. Higher than 0, max 29999.
--- @field SameSearchAction integer Same search deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field MyinfoMessages integer MyINFO deflood messages count. Higher than 0, max 29999.
--- @field MyinfoTime integer MyINFO deflood time. Higher than 0, max 29999.
--- @field MyinfoAction integer MyINFO deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field GetnicklistMessages integer GetNickList deflood messages count. Higher than 0, max 29999.
--- @field GetnicklistTime integer GetNickList deflood time. Higher than 0, max 29999. 
--- @field GetnicklistAction integer GetNickList deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field NewConnectionsCount integer Connection deflood connecions count. Higher than 0, max 999. 
--- @field NewConnectionsTime integer Connection deflood time. Higher than 0, max 999.
--- @field DefloodWarningCount integer Deflood warnings count. Higher than 0, max 29999.
--- @field DefloodWarningAction integer Deflood warnings action. 0 = disconnect, 1 = kick, 2 = tempban, 3 = permban. Max 3.
--- @field DefloodTempBanTime integer Deflood tempban time. Higher than 0.
--- @field GlobalMainChatMessages integer Global main chat messages count. Higher than 0, max 29999.
--- @field GlobalMainChatTime integer Global main chat time. Higher than 0, max 29999.
--- @field GlobalMainChatTimeout integer Global main chat timeout. Higher than 0, max 29999.
--- @field GlobalMainChatAction integer Global main chat action. 0 = disabled, 1 = lock chat, 2 = send to ops with ips. Max 2.
--- @field MinSearchLen integer Min search length.
--- @field MaxSearchLen integer Max search length.
--- @field MinNickLen integer Min nick length. Max 64.
--- @field MaxNickLen integer Max nick length. Max 64.
--- @field BruteForcePassProtectBanType integer Brute force password protection ban type. 0 = disabled, 1 = permban, 2 = tempban. Max 2.
--- @field BruteForcePassProtectTempBanTime integer Brute force password protection temp ban time. Higher than 0.
--- @field MaxPmCountToUser integer Max pm count to same user per minute.
--- @field MaxSimultaneousLogins integer Max simultaneous logins. Higher than 0, max 500.
--- @field MainChatMessages2 integer Secondary main chat deflood messages count. Higher than 0, max 29999.
--- @field MainChatTime2 integer Secondary main chat deflood time. Higher than 0, max 29999.
--- @field MainChatAction2 integer Secondary main chat deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field PmMessages2 integer Secondary private message deflood messages count. Higher than 0, max 29999.
--- @field PmTime2 integer Secondary private message deflood time. Higher than 0, max 29999.
--- @field PmAction2 integer Secondary private message deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SearchMessages2 integer Secondary search deflood messages count. Higher than 0, max 29999.
--- @field SearchTime2 integer Secondary search deflood time. Higher than 0, max 29999.
--- @field SearchAction2 integer Secondary search deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field MyinfoMessages2 integer Secondary myINFO deflood messages count. Higher than 0, max 29999.
--- @field MyinfoTime2 integer Secondary myINFO deflood time. Higher than 0, max 29999.
--- @field MyinfoAction2 integer Secondary myINFO deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field MaxMyinfoLen integer Maximum MyINFO length. Min 64, max 512.
--- @field CtmMessages integer Primary ConnectToMe deflood count. Higher than 0, max 29999.
--- @field CtmTime integer Primary ConnectToMe deflood time. Higher than 0, max 29999.
--- @field CtmAction integer Primary ConnectToMe deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field CtmMessages2 integer Secondary ConnectToMe deflood count. Higher than 0, max 29999.
--- @field CtmTime2 integer Secondary ConnectToMe deflood time. Higher than 0, max 29999.
--- @field CtmAction2 integer Secondary ConnectToMe deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field RctmMessages integer Primary RevConnectToMe deflood count. Higher than 0, max 29999.
--- @field RctmTime integer Primary RevConnectToMe deflood time. Higher than 0, max 29999.
--- @field RctmAction integer Primary RevConnectToMe deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field RctmMessages2 integer Secondary RevConnectToMe deflood count. Higher than 0, max 29999.
--- @field RctmTime2 integer Secondary RevConnectToMe deflood time. Higher than 0, max 29999.
--- @field RctmAction2 integer Secondary RevConnectToMe deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field MaxCtmLen integer Maximum ConnectToMe length. Higher than 0, max 512.
--- @field MaxRctmLen integer Maximum RevConnectToMe length. Higher than 0, max 512.
--- @field SrMessages integer Primary SR deflood count. Higher than 0, max 29999.
--- @field SrTime integer Primary SR deflood time. Higher than 0, max 29999.
--- @field SrAction integer Primary SR deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field SrMessages2 integer Secondary SR deflood count. Higher than 0, max 29999.
--- @field SrTime2 integer Secondary SR deflood time. Higher than 0, max 29999.
--- @field SrAction2 integer Secondary SR deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field MaxSrLen integer Maximum SR length. Higher than 0, max 8192.
--- @field MaxDownAction integer Primary received data deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field MaxDownKB integer Primary received data deflood kB. Higher than 0, max 29999.
--- @field MaxDownTime integer Primary received data deflood time. Higher than 0, max 29999.
--- @field MaxDownAction2 integer Secondary received data deflood action. 0 = disabled, 1 = ignore, 2 = warn, 3 = disconnect, 4 = kick, 5 = tempban, 6 = permban. Max 6.
--- @field MaxDownKB2 integer Secondary received data deflood kB. Higher than 0, max 29999.
--- @field MaxDownTime2 integer Secondary received data deflood time. Higher than 0, max 29999.
--- @field ChatIntervalMessages integer Chat messages interval messages. Higher than 0, max 29999.
--- @field ChatIntervalTime integer Chat messages interval time. Higher than 0, max 29999.
--- @field PmIntervalMessages integer Private messages interval messages. Higher than 0, max 29999.
--- @field PmIntervalTime integer Private messages interval time. Higher than 0, max 29999.
--- @field SearchIntervalMessages integer Search interval count. Higher than 0, max 29999.
--- @field SearchIntervalTime integer Search interval time. Higher than 0, max 29999.
--- @field MaxConnsSameIp integer Maximum users from same IP. Higher than 0, max 256.
--- @field MinReconnTime integer Minimum reconnect time in seconds. Higher than 0, max 256.
--- @field DbRemoveOldRecords integer Remove records older than x days from database.

--- @type SetMantNumbers
SetMan.tNumbers = {}

--- @class SetMantStrings
--- @field HubName integer Hub name. Min length 1, max 256.
--- @field AdminNick integer Admin nick. Min length 1, max 64, $ is not allowed.
--- @field HubAddress integer Hub address. Min length 1, max 256.
--- @field TCPPorts integer TCP ports. Min length 1, max 64.
--- @field UDPPort integer UDP port. Min length 1, max 5.
--- @field HubDescription integer Hub description. Max length 256.
--- @field MainRedirectAddress integer Main redirect address. Max length 256.
--- @field HublistRegisterAddresses integer Hublist register servers. Max length 1024.
--- @field RegOnlyMessage integer Registered users only message. Min length 1, max 256.
--- @field RegOnlyRedirAddress integer Registered users only redirect address. Max length 256.
--- @field HubTopic integer Hub topic. Max length 256.
--- @field ShareLimitMessage integer Share limit message. Min length 1, max 256. Use %[min] for min share size and %[max] for max share size.
--- @field ShareLimitRedirAddress integer Share limit redirect address. Max length 256.
--- @field SlotLimitMessage integer Slot limit message. Min length 1, max 256. Use %[min] for min slots and %[max] for max slots.
--- @field SlotLimitRedirAddress integer Slot limit redirect address. Max length 256.
--- @field HubSlotRatioMessage integer Hub/slot ratio limit message. Min length 1, max 256. Use %[hubs] for hubs and %[slots] for slots.
--- @field HubSlotRatioRedirAddress integer Hub/slot ratio limit redirect address. Max length 256.
--- @field MaxHubsLimitMessage integer Max hubs limit message. Min length 1, max 256. Use %[hubs] for max hubs.
--- @field MaxHubsLimitRedirAddress integer Max hubs limit redirect address. Max length 256.
--- @field NoTagMessage integer No tag rule message. Min length 1, max 256.
--- @field NoTagRedirAddress integer No tag rule redirect address. Max length 256.
--- @field HubBotNick integer Hub bot nick. Min length 1, max 64, $ and space is not allowed.
--- @field HubBotDescription integer Hub bot description. Max length 64, $ is not allowed.
--- @field HubBotEmail integer Hub bot email. Max length 64, $ is not allowed.
--- @field OpChatNick integer OpChat bot nick. Min length 1, max 64, $ and space is not allowed.
--- @field OpChatDescription integer OpChat bot description. Max length 64, $ is not allowed.
--- @field OpChatEmail integer OpChat bot email. Max length 64, $ is not allowed.
--- @field TempBanRedirAddress integer Temp ban redirect address. Max length 256.
--- @field PermBanRedirAddress integer Perm ban redirect address. Max length 256.
--- @field ChatCommandsPrefixes integer Chat commands prefixes. Min length 1, max 5.
--- @field HubOwnerEmail integer Hub owner email. Max length 64.
--- @field NickLimitMessage integer Nick limit message. Min length 1, max 256. Use %[min] for min length and %[max] for max length.
--- @field NickLimitRedirAddress integer Nick limit redirect address. Max length 256.
--- @field MessageToAddToBanMessage integer Additional message to ban message. Max lenght 256.
--- @field Language integer Language. When language is default then return nil.
--- @field IPv4Address integer TCP/IP version 4 address.
--- @field IPv6Address integer TCP/IP version 6 address.
--- @field Encoding integer Character encoding for non-unicode texts.
--- @field PostgresHost integer PostgreSQL host.
--- @field PostgresPort integer PostgreSQL port.
--- @field PostgresDBName integer PostgreSQL database name.
--- @field PostgresUser integer PostgreSQL database user.
--- @field PostgresPass integer PostgreSQL database password.
--- @field MySQLHost integer MySQL host.
--- @field MySQLPort integer MySQL port.
--- @field MySQLDBName integer MySQL database name.
--- @field MySQLUser integer MySQL database user.
--- @field MySQLPass integer MySQL database password.

--- @type SetMantStrings
SetMan.tStrings = {}

--- @class ProfMantPermissions
--- @field IsOperator integer User have key / is OP
--- @field NoDefloodGetnicklist integer No GetNickList Deflood
--- @field NoDefloodMyinfo integer No MyINFO Deflood
--- @field NoDefloodSearch integer No Search Deflood
--- @field NoDefloodPm integer No PM Deflood
--- @field NoDefloodMainChat integer No Main Chat Deflood
--- @field MassMsg integer Mass Message
--- @field Topic integer Topic
--- @field TempBan integer TempBan
--- @field ReloadTxtFiles integer Reload text files
--- @field NoTagCheck integer No Tag check
--- @field TempUnban integer TempUnban
--- @field DelRegUser integer DelRegUser
--- @field AddRegUser integer AddRegUser
--- @field NoChatLimits integer No ChatLimits
--- @field NoMaxHubsCheck integer No MaxHubs Check
--- @field NoSlotHubRatioCheck integer No Slot/Hub ratio Check
--- @field NoSlotCheck integer No SlotCheck
--- @field NoShareLimit integer No ShareLimit check
--- @field ClrPermBan integer Clear PermBan
--- @field ClrTempBan integer Clear TempBan
--- @field GetInfo integer GetInfo
--- @field GetBans integer Get Bans
--- @field ScriptControl integer Start/Stop/Restart script(s)
--- @field RstHub integer Restart hub
--- @field TempOp integer TempOP
--- @field GagUngag integer Gag, Ungag
--- @field Redirect integer Redirect
--- @field Ban integer Ban
--- @field Kick integer Kick
--- @field Drop integer Drop
--- @field EnterIfHubFull integer Enter full hub
--- @field EnterIfIpBan integer Enter hub if IP banned
--- @field AllowedOpChat integer Allowed for OpChat
--- @field SendAllUsersIp integer Send all users IP
--- @field RangeBan integer Range ban
--- @field RangeUnban integer Range unban
--- @field RangeTempBan integer Range temp ban
--- @field RangeTempUnban integer Range temp unban
--- @field GetRangeBans integer Get range perm bans
--- @field ClrRangePermBans integer Clear range perm bans
--- @field ClrRangeTempBans integer Clear range temp bans
--- @field Unban integer Unban
--- @field NoSearchLimits integer No search length limits.
--- @field SendLongMyinfos integer Send full myinfos
--- @field NoIpCheck integer No IP checking in connection and search request.
--- @field Close integer Close
--- @field NoDefloodCtm integer No ConnectToMe deflood.
--- @field NoDefloodRctm integer No RevConnectToMe deflood.
--- @field NoDefloodSr integer No search reply deflood.
--- @field NoDefloodRecv integer No received data deflood.
--- @field NoChatInterval integer No chat interval.
--- @field NoPmInterval integer No private message interval.
--- @field NoSearchInterval integer No search interval.
--- @field NoMaxUsrSameIp integer No maximum users from same IP.
--- @field NoReconnTime integer No reconnect time.

--- @type ProfMantPermissions
ProfMan.tPermissions = {}

--- @alias PtokaXArrival fun(tUser: User, sData: string): boolean?

