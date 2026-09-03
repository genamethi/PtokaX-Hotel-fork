local utils = require("utils")
local console = require("pxapi.console")

local function buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
end

vim.keymap.set("n", "<leader>ps", function()
  console.send(buffer_text())
end, { desc = "PtokaX send buffer" })

vim.keymap.set("v", "<leader>ps", function()
  console.send(utils.get_visual_selection())
end, { desc = "PtokaX send selection" })

vim.keymap.set("n", "<leader>pS", function()
  console.send(buffer_text(), { cache = true })
end, { desc = "PtokaX send buffer, cached sudo" })

vim.keymap.set("v", "<leader>pS", function()
  console.send(utils.get_visual_selection(), { cache = true })
end, { desc = "PtokaX send selection, cached sudo" })

vim.keymap.set("n", "<leader>pl", function()
  console.send(vim.api.nvim_get_current_line())
end, { desc = "PtokaX send line" })

vim.keymap.set("n", "<leader>pL", function()
  console.send(vim.api.nvim_get_current_line(), { cache = true })
end, { desc = "PtokaX send line, cached sudo" })

vim.keymap.set("n", "<leader>pp", function()
  console.pick()
end, { desc = "PtokaX attach to a script" })

vim.keymap.set("n", "<leader>pP", function()
  console.pick({ cache = true })
end, { desc = "PtokaX attach to a script, cached sudo" })

vim.keymap.set("n", "<leader>pd", function()
  console.detach()
end, { desc = "PtokaX detach this buffer" })

vim.keymap.set("n", "<leader>pj", function()
  console.journal()
end, { desc = "PtokaX console journal" })

vim.keymap.set("n", "<leader>pi", function()
  console.pick_instance()
end, { desc = "PtokaX pick instance" })

local ARG_TYPE = { s = "string", i = "integer", u = "integer", b = "boolean",
                   n = "number", f = "function", t = "table" }

vim.keymap.set("n", "<leader>pa", function()
  local line = vim.api.nvim_get_current_line()
  local args = line:match("^%s*function%s+[%w_.:]+%s*%(([^)]*)%)")
  if not args then
    return utils.warn("no function declaration on this line")
  end
  local out = {}
  local indent = line:match("^%s*")
  for raw in args:gmatch("[^,]+") do
    local a = raw:match("^%s*(.-)%s*$")
    if a ~= "" and a ~= "..." then
      local t = a == "tUser" and "User" or (ARG_TYPE[a:sub(1, 1)] or "any")
      out[#out + 1] = ("%s--- @param %s %s"):format(indent, a, t)
    end
  end
  if #out == 0 then
    return utils.warn("no arguments to annotate")
  end
  local row = vim.api.nvim_win_get_cursor(0)[1]
  vim.api.nvim_buf_set_lines(0, row - 1, row - 1, false, out)
  utils.info("annotated %d parameter%s", #out, #out == 1 and "" or "s")
end, { desc = "PtokaX annotate handler params" })
