local socksleep = require 'socket'.sleep

local sleep = function (msec)
  assert (type(msec) == 'number', "invalid msec parameter for sleep")

  socksleep (msec * 1E-3)
end

return sleep
