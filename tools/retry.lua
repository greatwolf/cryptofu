local log = require 'tools.logger'

local find = function (t, msg)
  for _, m in ipairs(t) do
    if msg:match (m) then return true end
  end
  return false
end

-- Retries a function/action if it fails for given reason,
-- up to retry_limit. 'context' holds a list of errors to match against.
-- If the error thrown is one of the error strings in context, the retry is
-- attempted.
local wrap_retry = function (f, reasons, retry_limit)
  local lognote, logwarn = log "Note", log "Warning"
  return function (...)
    local attempts = 0
    local res
    while attempts < retry_limit do
      res = {pcall (f, ...)}
      attempts = attempts + 1
      if res[1] then
        lognote._if (attempts > 1, "retry succeeds after " .. attempts ..  " attempt(s).")
        return select (2, unpack (res)) 
      end
      if not find (reasons, res[2]) then break end
    end
    logwarn._if (attempts > 1, "retry fails after " .. attempts ..  " attempt(s).")
    error (res[2])
  end
end

local make_retry = function (obj, retry_limit, ...)
  retry_limit = retry_limit or 1
  local reasons = {...}

  for i, msg in ipairs (reasons) do
    reasons[i] = ": " .. msg
  end
  
  -- if given a func just wrap and return
  if type (obj) == "function" then
    return wrap_retry (obj, reasons, retry_limit)
  end
  
  -- handle table case
  local mt = {}
  mt.__index = function (t, k)
    t[k] = obj[k]
    if type (t[k]) == "function" then
      t[k] = wrap_retry (t[k], reasons, retry_limit)
    end
    return rawget (t, k)
  end
  
  return setmetatable ({}, mt)
end

return make_retry
