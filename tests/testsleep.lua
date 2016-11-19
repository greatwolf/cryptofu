require 'pl.app'.require_here ".."
local utest = require 'tools.unittest'
local sleep = require 'tools.sleep'

local function stopwatch (f, ...)
  local clock       = os.clock
  local start, stop = clock ()
  f (...)
  stop = clock () * 1E3

  return stop - start * 1E3
end

local make_delaytest = function (delay, tolerance)
  return function ()
    local elapse = stopwatch (sleep, delay)
    local lowerdelay, upperdelay = delay * (1 - tolerance), delay * (1 + tolerance)
    assert (lowerdelay < elapse, ("%.9f"):format (elapse))
    assert (elapse < upperdelay, ("%.9f"):format (elapse))
  end
end

utest.group "sleep"
{
  test_delay2sec    = make_delaytest (2000, 0.0001),
  test_delay1sec    = make_delaytest (1000, 0.0001),
  test_delay750msec = make_delaytest (750, 0.0001),
  test_delay500msec = make_delaytest (500, 0.0001),
  test_delay101msec = make_delaytest (101, 0.0001),
  test_delay13msec  = make_delaytest (13, 0.0001),

  test_missingparm = function ()
    local r, errmsg = pcall (sleep)
    assert (not r)
    assert (errmsg:match "sleep%.lua.-invalid msec parameter for sleep", errmsg)
  end,

  test_badparam = function ()
    local r, errmsg = pcall (sleep, "bad delay")
    assert (not r)
    assert (errmsg:match "sleep%.lua.-invalid msec parameter for sleep", errmsg)
  end,
}

utest.run "sleep"
