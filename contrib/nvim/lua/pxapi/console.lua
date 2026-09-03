local utils = require("utils")

local M = {}

M.socket = "/run/ptokax/%s-console.sock"
M.unit = "ptokax@%s.service"

M.instance = nil

local function sock(instance)
  return string.format(M.socket, instance)
end

local function attach(instance, name, buf)
  buf = buf or 0
  vim.b[buf].px_instance = instance
  vim.b[buf].px_script = name
  utils.info("attached to %s on %s", name, instance)
end

--- @param buf? integer
function M.detach(buf)
  buf = buf or 0
  if not vim.b[buf].px_script then
    return utils.warn("this buffer is not attached")
  end
  vim.b[buf].px_instance = nil
  vim.b[buf].px_script = nil
  utils.info("detached")
end

--- @param cb fun(instance: string)
function M.select_instance(cb)
  local found = utils.systemd_instances("ptokax")
  if #found == 0 then return utils.warn("no ptokax instances found") end
  if #found == 1 then
    M.instance = found[1]
    return cb(found[1])
  end
  vim.ui.select(found, { prompt = "PtokaX instance" }, function(choice)
    if choice then
      M.instance = choice
      cb(choice)
    end
  end)
end

--- @param cb fun(instance: string)
function M.with_instance(cb)
  if M.instance then return cb(M.instance) end
  M.select_instance(cb)
end

function M.pick_instance()
  M.instance = nil
  M.select_instance(function(instance) utils.info("instance: %s", instance) end)
end

function M.journal()
  M.with_instance(function(instance)
    utils.term_split({
      "journalctl", "-u", string.format(M.unit, instance),
      "PTOKAX_SUBSYSTEM=console", "-f",
    })
  end)
end

local function parse(out)
  local rows = {}
  for line in out:gmatch("[^\n]+") do
    local name, state, mem, path = line:match("^([^\t]+)\t([^\t]*)\t([^\t]*)\t(.+)$")
    if name then
      rows[#rows + 1] = { name = name, state = state, mem = mem, path = path }
    end
  end
  return rows
end

--- @param opts? table cache: reuse sudo's timestamp
function M.load(instance, row, opts)
  local ok, body = utils.sudo_sh(string.format("cat %s", vim.fn.shellescape(row.path)), opts)
  if not ok then return end
  local dir = string.format("%s/pxapi/%s", vim.fn.stdpath("cache"), instance)
  vim.fn.mkdir(dir, "p")
  local target = string.format("%s/%s", dir, row.name)
  local fd = io.open(target, "w")
  if not fd then
    return utils.warn("cannot write %s", target)
  end
  fd:write(body or "")
  fd:close()
  vim.cmd.edit(vim.fn.fnameescape(target))
  attach(instance, row.name, 0)
end

--- @param opts? table cache: reuse sudo's timestamp
function M.pick(opts)
  opts = opts or {}
  M.with_instance(function(instance)
    local out = utils.socket_query(sock(instance), "--!px list\n", opts)
    if not out then return end
    if out:match("^error:") then
      return utils.warn("%s", vim.trim(out))
    end
    local rows = parse(out)
    if #rows == 0 then
      return utils.warn("%s has no scripts", instance)
    end
    vim.ui.select(rows, {
      prompt = string.format("script on %s", instance),
      format_item = function(row)
        return string.format("%-28s %-8s %s", row.name, row.state, row.mem)
      end,
    }, function(row)
      if not row then return end
      if vim.fn.confirm("Load " .. row.name .. " into buffer?", "&Yes\n&No", 1) == 1 then
        M.load(instance, row, opts)
      else
        attach(instance, row.name, 0)
      end
    end)
  end)
end

--- @param text string
--- @param opts? table cache: reuse sudo's timestamp
function M.send(text, opts)
  opts = opts or {}
  local script = vim.b.px_script
  if not script then
    return M.with_instance(function(instance)
      if utils.socket_write(sock(instance), text, opts) then
        utils.info("sent to %s", instance)
      end
    end)
  end
  local instance = vim.b.px_instance or M.instance
  local body = text:gsub("[\r\n]+$", "") .. "\n--!px attach " .. script .. "\n"
  local out = utils.socket_query(sock(instance), body, opts)
  if not out then return end
  out = vim.trim(out)
  if out:match("^error:") then
    utils.warn("%s: %s", script, out)
  else
    utils.info("%s: %s", script, out ~= "" and out or "ok")
  end
end

return M
