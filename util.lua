local stringx = require 'pl.stringx'

--[[
  Various utility functions
--]]

-- Logging and debugging
-- Auto creates the name of the log
-- Specify where the log outputs by overriding log.writer; io.stderr is default
-- Usage: log.logname (condition, msg1, msg2, ...)
--  eg. log.warnif (2 > 1, "two is greater than one")
local create_logfunc = function (l, logname)
  local lower = logname:lower()
  -- check and default the writer
  if lower == "writer" then
    l.writer = io.stderr
    return rawget (l, "writer")
  end
  
  local camel = lower:sub(1, 1):upper() .. lower:sub(2)
  camel = stringx.endswith (camel, "_if") and camel:sub (1, -4) or camel
  local logfunc = function (cond, ...)
    local log_writer = l.writer
    if cond then
      log_writer:write ("  " .. camel .. ": ", ...)
      log_writer:write "\n"
    end
  end
  l[lower] = rawget(l, lower) or logfunc
  l[logname] = l[lower]
  return rawget(l, logname)
end

local log = setmetatable ({}, {__index = create_logfunc})

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
  return function (action, ...)
    local attempts = 0
    local res
    while attempts < context.attempts do
      res = {pcall (action, ...)}
      attempts = attempts + 1
      if res[1] then
        log.note_if (attempts > 1, "retry succeeds after " .. attempts ..  " attempt(s).")
        return select (2, unpack (res)) 
      end
      if not find (context, res[2]) then break end
    end
    log.warn_if (attempts > 1, "retry fails after " .. attempts ..  " attempt(s).")
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
  log = log,
  urlencode_parm = urlencode_parm,
  create_retry = create_retry,
}

return _M
