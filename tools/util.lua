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

-- Monotonically incrementing nonce every call to
-- new_nonce returns a nonce value higher than
-- the previous call.
-- Use a later date as epoch so more of the
-- 32bit int space can be used before it wraps
local epoch      = os.time { year = 2010, month = 1, day = 1 }
local now        = function () return os.time () - epoch end
local next_nonce = now() * 2
local function get_nonce (init_time)
  if init_time then
    next_nonce = init_time < 0 and (now() * 2) or init_time
  end
  next_nonce = next_nonce + 1
  return next_nonce
end

local _M = 
{
  urlencode_parm = urlencode_parm,
  map_transpose = map_transpose,
  nonce         = get_nonce,
}

return _M
