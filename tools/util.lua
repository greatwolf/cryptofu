--[[
  Various utility functions
--]]

-- Takes a table of url parameter pairs and encodes them into
-- a string suitable for appending to a url's path.
local function urlencode_parm(t, delim)
  assert (type(t) == "table")
  local parm = {}
  for k, v in pairs(t) do
    table.insert (parm, k .. "=" .. v)
  end
  return table.concat (parm, delim or "&")
end

local _M = 
{
  urlencode_parm = urlencode_parm,
}

return _M
