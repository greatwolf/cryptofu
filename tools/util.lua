local log = require 'tools.logger'
--[[
  Various utility functions
--]]

local find = function (t, msg)
  for _, m in ipairs(t) do
    if msg:match (m) then return true end
  end
  return false
end

-- Retries a function/action if it fails for given reason,
-- up to max_retries. 'context' holds a list of errors to match against.
-- If the error thrown is one of the error strings in context, the retry is
-- attempted.
local max_retries = 1
local create_retry = function (context)
  assert (type(context) == "table")
  context.attempts = context.attempts or max_retries
  for i, msg in ipairs (context) do
    context[i] = ": " .. msg
  end
  local lognote, logwarn = log "Note", log "Warning"
  return function (action, ...)
    local attempts = 0
    local res
    while attempts < context.attempts do
      res = {pcall (action, ...)}
      attempts = attempts + 1
      if res[1] then
        lognote._if (attempts > 1, "retry succeeds after " .. attempts ..  " attempt(s).")
        return select (2, unpack (res)) 
      end
      if not find (context, res[2]) then break end
    end
    logwarn._if (attempts > 1, "retry fails after " .. attempts ..  " attempt(s).")
    error (res[2])
  end
end

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
  create_retry = create_retry,
}

return _M
