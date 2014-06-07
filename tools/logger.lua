-- Logging and debugging
-- Specify where the log outputs by overriding log.writer; defaults to io.stdout
-- Usage: log (msg1, msg2, ...)
--        log._if (condition, msg1, msg2, ...)

local log_builder = function (name, writer)
  name = name and name..":" or ""
  writer = writer or io.stdout
  local date = os.date

  local log = function (...)
    local timestamp = date ("%m-%d %H:%M:%S")
    writer:write (string.format ("[%s] %s ", timestamp, name))
    writer:write (...)
    writer:write "\n"
  end

  local log_if = function (cond, ...)
    if cond then log (...) end
  end

  local logger = 
  {
    __call = function (_, ...) log (...) end,
    _if = log_if
  }
  return setmetatable (logger, logger)
end

return log_builder
