local shared = require("editable-telescope.args")
local M = {}

local values = { g = true, glob = true, iglob = true, t = true, type = true,
  T = true, ["type-not"] = true, ["max-depth"] = true, ["max-filesize"] = true }
local switches = { hidden = true, ["no-hidden"] = true, ["no-ignore"] = true,
  ignore = true, L = true, follow = true, ["no-follow"] = true }

function M.parse(input)
  local args, err = shared.split(input, true)
  if not args then return nil, err end
  err = M.validate(args)
  if err then return nil, err end
  return args
end

function M.validate(args)
  local index = 1
  while index <= #args do
    local arg = args[index]
    if type(arg) ~= "string" then return "rg arguments must be strings" end
    local name, value = arg:match("^%-%-([%w-]+)=(.*)$")
    name = name or arg:match("^%-%-([%w-]+)$") or arg:match("^%-([gtTL])$")
    if values[name] then
      if value == nil then index, value = index + 1, args[index + 1] end
      if type(value) ~= "string" or value == "" or value:sub(1, 1) == "-" then
        return "missing value for rg flag: " .. arg
      end
    elseif not switches[name] or value ~= nil then
      return "unsupported rg argument: " .. arg
    end
    index = index + 1
  end
end

return M
