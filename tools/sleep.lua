local sockselect = require 'socket'.select

local sleep = function (msec)
  assert (type(msec) == 'number', "invalid msec parameter for sleep")

  sockselect (nil, nil, msec * 1E-3)
end

return sleep
