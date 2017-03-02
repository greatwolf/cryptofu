local log = require 'tools.logger'

local find = function (t, msg)
  for _, m in ipairs(t) do
    if msg:match (m) then return true end
  end
  return false
end

-- Retries a function/action if it fails for given reason,
-- up to retry_limit. 'reasons' holds a list of errors to match against.
-- If the error thrown is one of the error strings in reasons, the retry is
-- attempted.
-- Takes an optional 'output_writer' for logging retry status
local retry_wrapfunc = function (f, reasons, retry_limit, output_writer)
  local unpack = unpack or table.unpack
  if output_writer then
    return function (...)
      local attempts = 0
      local res
      while attempts < retry_limit do
        res = table.pack (pcall (f, ...))
        attempts = attempts + 1
        if res[1] then
          if attempts > 1 then
            output_writer ("retry succeeds after " .. attempts ..  " attempt(s).")
          end
          return unpack (res, 2, res.n)
        end
        output_writer (res[2]:match "%d+: (.+)")
        if not find (reasons, res[2]) then break end
      end
      if attempts > 1 then
        output_writer ("retry fails after " .. attempts ..  " attempt(s).")
      end
      error (res[2], 2)
    end
  else
    return function (...)
      local attempts = 0
      local res
      while attempts < retry_limit do
        res = table.pack (pcall (f, ...))
        attempts = attempts + 1
        if res[1] then
          return unpack (res, 2, res.n)
        end
        if not find (reasons, res[2]) then break end
      end
      error (res[2], 2)
    end
  end
end

local retry_wrapmethod = function (wrapper, real_self, f, reasons, retry_limit, output_writer)
  -- Replace the wrapper table with the real object before function call
  -- This is to prevent the retry attempts from multiplying due to
  -- methods that might calling other methods on the same object.
  -- The wrapper should only apply to outside code calling into object methods;
  -- methods calling other methods should get the real object so the retry doesn't
  -- trigger and multiple.
  local f = retry_wrapfunc (f, reasons, retry_limit, output_writer)
  return function (self, ...)
    if self == wrapper then self = real_self end
    return f (self, ...)
  end
end

local make_retry = function (obj, retry_limit, output_writer, ...)
  retry_limit = retry_limit or 1
  local reasons
  if type (output_writer) == "string" then
    reasons = {output_writer, ...}
    output_writer = nil
  else reasons = {...}
  end

  for i, msg in ipairs (reasons) do
    reasons[i] = ": " .. msg
  end
  
  -- if given a func just wrap and return
  if type (obj) == "function" then
    return retry_wrapfunc (obj, reasons, retry_limit, output_writer)
  end
  
  -- handle table case
  local wrapper = {}
  local mt = {}
  mt.__index = function (t, k)
    local lvalue = obj[k]
    t[k] = lvalue
    if type (lvalue) == "function" then
      t[k] = retry_wrapmethod (wrapper, obj, lvalue, reasons, retry_limit, output_writer)
    end
    return rawget (t, k)
  end
  
  return setmetatable (wrapper, mt)
end

return make_retry
