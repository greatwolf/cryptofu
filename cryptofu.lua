require 'luarocks_path'
local log = require 'tools.logger' ()
local dispatcher = require 'dispatcher'
local config = "config.lua"
local dump = require 'pl.pretty'.dump

local loadmodule = function (name)
  return pcall (function ()
    local sandbox = {}
    local mod_table = setfenv (assert (loadfile (name)), sandbox) ()
    setmetatable (sandbox, { __index = function (t, v)
                                        t[v] = v == "_G" and sandbox or _G[v]
                                        return rawget (t, v) 
                                       end })

    assert (mod_table.main)
    dispatcher.addtask (mod_table.main, mod_table.interval)
    if mod_table.startup then
      table.insert (dispatcher.startup_tasks, mod_table.startup)
    end
    if mod_table.shutdown then
      table.insert (dispatcher.shutdown_tasks, mod_table.shutdown)
    end
  end)
end

local loadconfig = function (cfg_file)
  local modules = {}
  local noerr, errmsg = pcall (function ()
    log ("Reading ", cfg_file)
    setfenv (assert (loadfile (cfg_file)), modules) ()
    modules = modules.modules
  end)
  log._if (not noerr, errmsg)
  if not noerr then return end

  for _, mod in ipairs (modules) do
    log ("Loading ", mod)
    local noerr, errmsg = loadmodule (mod)
    log._if (not noerr, errmsg)
  end
end


print "CryptoFu Trader"
loadconfig (config)
dispatcher.startup()
dispatcher.mainloop()
dispatcher.shutdown()
