--[[
  Coroutine dispatcher design questions, approach and constraints:
    - Dispatcher will have startup, mainloop and cleanup sections.
      Tasks can supply corresponding functions that runs for each of
      these sections.
    - Tasks that propogates an error are considered dead and will 
      be removed on next iteration.
    - Each task should be a wrapped closure or coroutine?
      Leaning towards closure. A timeup parameter will be bound to the closure.
    - Each task needs a timeup parameter affecting how often it's executed.
    - Need a way to add/remove tasks from the dispatcher list.
--]]

require 'luarocks_path'
local ffi = require 'ffi'


ffi.cdef [[void Sleep (int ms);]]
local Sleep = ffi.C.Sleep
local timeout_period = 100

local dispatcher = { startup_tasks = {}, shutdown_tasks = {}, tasks = {} }

function dispatcher.addtask (f, timesup)
  timesup = timesup or timeout_period / 1000
  local log = require 'tools.logger' "Dispatcher"
  local co = coroutine.create (f)
  local clock = os.clock
  local resume, status = coroutine.resume, coroutine.status
  local next_run = timesup + clock ()
  local task = function ()
    if clock () > next_run then
      local noerr, errmsg = resume (co)
      log._if (not noerr, errmsg)
      next_run = timesup + clock ()
    end
    return status (co)
  end
  table.insert (dispatcher.tasks, task)
end

function dispatcher.startup ()
  for _, each in ipairs (dispatcher.startup_tasks) do
    each ()
  end
end

function dispatcher.mainloop ()
  local tasks = dispatcher.tasks
  local front = #tasks
  while #tasks > 0 do
    local status = tasks[front] ()
    if status == "dead" then
      table.remove (tasks, front)
    end
    front = front == 1 and #tasks or (front - 1)
    Sleep (timeout_period)
  end
end

function dispatcher.shutdown ()
  for _, each in ipairs (dispatcher.shutdown_tasks) do
    each ()
  end
end

return dispatcher
