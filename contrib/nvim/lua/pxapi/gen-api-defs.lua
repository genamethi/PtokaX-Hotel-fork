-- Generate LuaCATS definitions for the hub's Lua API from the scripting docs.
--
--   lua contrib/nvim/gen-api-defs.lua scripting.docs/scripting-interface.txt \
--       > contrib/nvim/ptokax-api.lua
--
-- Types come from the Hungarian prefix on each name, which the docs use
-- consistently. Anything unrecognised falls back to any, so a bad guess shows
-- up as a missing type rather than a wrong one.

local src = assert(arg[1], "usage: gen-api-defs.lua <scripting-interface.txt>")

local PREFIX = {
  s = "string", i = "integer", u = "integer", b = "boolean",
  n = "number", f = "function", t = "table",
}

local CLASS_PARAM = { tUser = "User" }

local OVERRIDE = {
  Version = "string", BuildNumber = "integer",
  uptr = "lightuserdata", tIPs = "string[]",
  tProfilePermissions = "ProfilePermissions",
}

local function typeof(name)
  if OVERRIDE[name] then return OVERRIDE[name] end
  if CLASS_PARAM[name] then return CLASS_PARAM[name] end
  local p = name:sub(1, 1)
  return PREFIX[p] or "any"
end

local function params(argstr)
  local out = {}
  if not argstr or argstr:match("^%s*$") then return out end
  for raw in argstr:gmatch("[^,]+") do
    local a = raw:match("^%s*(.-)%s*$")
    -- the docs write alternatives as sNick/sIP
    local first = a:match("^([%w_]+)") or a
    out[#out + 1] = { name = first, type = typeof(first) }
  end
  return out
end

local RETURNS = {
  ["Core.GetBots"] = "BotInfo[]",
  ["Core.GetActualUsersPeak"] = "integer", ["Core.GetMaxUsersPeak"] = "integer",
  ["Core.GetCurrentSharedSize"] = "integer", ["Core.GetUsersCount"] = "integer",
  ["Core.GetUpTime"] = "integer",
  ["Core.GetHubIP"] = "string?", ["Core.GetHubIPs"] = "string[]?",
  ["Core.GetHubSecAlias"] = "string", ["Core.GetPtokaXPath"] = "string",
  ["Core.GetOnlineNonOps"] = "User[]", ["Core.GetOnlineOps"] = "User[]",
  ["Core.GetOnlineRegs"] = "User[]", ["Core.GetOnlineUsers"] = "User[]",
  ["Core.GetUser"] = "User?", ["Core.GetUsers"] = "User[]?",
  ["Core.GetUserValue"] = "any", ["Core.GetUserAllData"] = "boolean?",
  ["Core.GetUserData"] = "boolean?", ["Core.SetUserInfo"] = "boolean?",

  ["SetMan.GetMOTD"] = "string?", ["SetMan.GetBool"] = "boolean?",
  ["SetMan.GetNumber"] = "integer?", ["SetMan.GetString"] = "string?",
  ["SetMan.GetMinShare"] = "integer", ["SetMan.GetMaxShare"] = "integer",
  ["SetMan.GetOpChat"] = "OpChatInfo", ["SetMan.GetHubBot"] = "HubBotInfo",

  ["RegMan.GetRegsByProfile"] = "RegisteredUser[]", ["RegMan.GetNonOps"] = "RegisteredUser[]",
  ["RegMan.GetOps"] = "RegisteredUser[]", ["RegMan.GetRegs"] = "RegisteredUser[]",
  ["RegMan.GetReg"] = "RegisteredUser?",

  ["BanMan.GetBans"] = "Ban[]", ["BanMan.GetTempBans"] = "Ban[]",
  ["BanMan.GetPermBans"] = "Ban[]",
  ["BanMan.GetBan"] = "Ban|Ban[]|nil", ["BanMan.GetPermBan"] = "Ban|Ban[]|nil",
  ["BanMan.GetTempBan"] = "Ban|Ban[]|nil",
  ["BanMan.GetRangeBans"] = "RangeBan[]", ["BanMan.GetTempRangeBans"] = "RangeBan[]",
  ["BanMan.GetPermRangeBans"] = "RangeBan[]",
  ["BanMan.GetRangeBan"] = "RangeBan?", ["BanMan.GetRangePermBan"] = "RangeBan?",
  ["BanMan.GetRangeTempBan"] = "RangeBan?",

  ["ProfMan.AddProfile"] = "integer?", ["ProfMan.GetProfile"] = "Profile?",
  ["ProfMan.GetProfiles"] = "Profile[]",
  ["ProfMan.GetProfilePermission"] = "boolean?",
  ["ProfMan.GetProfilePermissions"] = "ProfilePermissions",

  ["TmrMan.AddTimer"] = "integer?",

  ["ScriptMan.GetScript"] = "ScriptInfo", ["ScriptMan.GetScripts"] = "ScriptInfo[]",

  ["IP2Country.GetCountryCode"] = "string?", ["IP2Country.GetCountryName"] = "string?",
}

local function returns(desc)
  local d = desc:lower()
  if d:match("return nil when failed") or d:match("return true") or
     d:match("true if success") or d:match("true when success") then
    return "boolean?"
  elseif d:match("return table") or d:match("return.*as.*table") then
    return "table"
  elseif d:match("string or nil") then
    return "string?"
  elseif d:match("^%s*return ") then
    if d:match("count") or d:match("size") or d:match("time") or d:match("number") then
      return "integer?"
    end
    return "any"
  end
  return nil
end

local lines = {}
-- the docs are CRLF
for line in io.lines(src) do lines[#lines + 1] = (line:gsub("\r$", "")) end

local out = {}
local function emit(s) out[#out + 1] = s end

local PREAMBLE = [[
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
]]

emit("--- @meta")
emit("--- PtokaX hub scripting API. Generated from scripting-interface.txt.")
emit("--- Regenerate with contrib/nvim/gen-api-defs.lua rather than editing.")
emit("")
emit(PREAMBLE)

-- classes described as flat field lists
local CLASSES = {
  ["User."] = "User", ["RegisteredUser."] = "RegisteredUser",
  ["Ban."] = "Ban", ["RangeBan."] = "RangeBan", ["Profile."] = "Profile",
  ["ProfilePermissions."] = "ProfilePermissions",
}
local NAMESPACES = {
  ["Core."] = "Core", ["SetMan."] = "SetMan", ["RegMan."] = "RegMan",
  ["BanMan."] = "BanMan", ["ProfMan."] = "ProfMan", ["TmrMan."] = "TmrMan",
  ["UDPDbg."] = "UDPDbg", ["ScriptMan."] = "ScriptMan",
  ["IP2Country."] = "IP2Country",
}

local i = 1
local section, kind = nil, nil

local function close_section()
  if section and kind == "ns" then
    emit("")
    emit(("--- @type %sLib"):format(section))
    emit(("%s = {}"):format(section))
    emit("")
  end
  section, kind = nil, nil
end
local seen = {}
local consts = {}

while i <= #lines do
  local line = lines[i]
  if CLASSES[line] then
    close_section()
    section, kind = CLASSES[line], "class"
    emit("--- @class " .. section)
    seen = {}
  elseif NAMESPACES[line] then
    close_section()
    section, kind = NAMESPACES[line], "ns"
    emit("--- @class " .. section .. "Lib")
    seen = {}
  elseif line:match("^%-%-%-%-") or line:match("^%-+$") then
    -- underline, skip
  elseif line:match("IDs for") then
    close_section()
    kind = "consts"
  elseif line:match("^Functions%s*$") then
    close_section()
    kind = "callbacks"
  elseif kind == "class" and section then
    local f, d = line:match("^(%w+)%s+%-%s*(.*)$")
    if f then
      local t = typeof(f)
      if d:lower():match("or nil") or d:lower():match("^true or nil") then t = t .. "?" end
      emit(("--- @field %s %s %s"):format(f, t, d))
    end
  elseif kind == "ns" and section then
    local name, args, desc = line:match("^([%w_]+)%s*%(([^)]*)%)%s*%-?%s*(.*)$")
    if not name then
      name, desc = line:match("^([%w_]+)%s+%-%s*(.*)$")
    end
    if name then
      local sig
      if args then
        local ps = params(args)
        local parts = {}
        for _, p in ipairs(ps) do parts[#parts + 1] = p.name .. ": " .. p.type end
        local r = RETURNS[section .. "." .. name] or returns(desc or "")
        sig = ("fun(%s)%s"):format(table.concat(parts, ", "), r and (": " .. r) or "")
      else
        sig = typeof(name)
      end
      if seen[name] then
        emit(("--- @overload %s"):format(sig))
      else
        seen[name] = true
        if desc and desc ~= "" then emit("--- " .. desc) end
        emit(("--- @field %s %s"):format(name, sig))
      end
    end
  elseif kind == "callbacks" then
    local name, args, desc = line:match("^([%w_]+)%s*%(([^)]*)%)%s*%-%s*(.*)$")
    if name then
      local parts = {}
      for _, prm in ipairs(params(args)) do
        parts[#parts + 1] = prm.name .. ": " .. prm.type
      end
      local ret = desc:match("return true") and ": boolean?" or ""
      emit("--- " .. desc)
      emit(("--- @type fun(%s)%s"):format(table.concat(parts, ", "), ret))
      emit(name .. " = nil")
      emit("")
    end
  elseif kind == "consts" then
    local ns, tbl, key, desc = line:match("^([%w_]+)%.(t[%w_]+)%.([%w_]+)%s*%-%s*(.*)$")
    if ns then
      consts[ns] = consts[ns] or {}
      consts[ns][tbl] = consts[ns][tbl] or {}
      table.insert(consts[ns][tbl], { key = key, desc = desc })
    end
  end
  i = i + 1
end

close_section()

for ns, tables in pairs(consts) do
  for tbl, keys in pairs(tables) do
    emit(("--- @class %s%s"):format(ns, tbl))
    for _, k in ipairs(keys) do
      emit(("--- @field %s integer %s"):format(k.key, k.desc))
    end
    emit("")
    emit(("--- @type %s%s"):format(ns, tbl))
    emit(("%s.%s = {}"):format(ns, tbl))
    emit("")
  end
end

-- the hub calls these; a script defines the ones it wants
emit("--- @alias PtokaXArrival fun(tUser: User, sData: string): boolean?")
emit("")

print(table.concat(out, "\n"))
