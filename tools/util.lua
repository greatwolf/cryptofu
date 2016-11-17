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

local function map_transpose (t, rename)
  if #t == 0 then return t end
  local transposed = {}
  -- get the field names
  for k in pairs (t[1]) do
    if type (k) == "string" then
      transposed[k] = {}
    end
  end
  -- now do the transpose
  for k in pairs (transposed) do
    for _, item in ipairs (t) do
      table.insert (transposed[k], item[k])
    end
  end
  -- perform optional field renames
  if rename then
    for k, v in pairs (transposed) do
      if rename[k] then
        transposed[ rename[k] ], transposed[k] = v
      end
    end
  end
  return transposed
end

-- Monotonically incrementing nonce
-- every call to new_nonce returns a 
-- nonce value higher than the previous call
local nonce
local function new_nonce (init_time)
  nonce = (nonce or init_time or os.time() * 2) + 1
  return nonce
end

local _M = 
{
  urlencode_parm = urlencode_parm,
  map_transpose = map_transpose,
  new_nonce     = new_nonce,
}

return _M
