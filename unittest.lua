local ffi = require 'ffi'
local clock = os.clock
local print, pcall = print, pcall
ffi.cdef [[void Sleep (int ms);]]
local Sleep = ffi.C.Sleep
local sleep_delay = 0 -- ms

local function run_single (testgroup, testname)
  assert (testgroup[testname])
  io.write ("Running " .. testname .. "... ")
  local start = clock()
  local noerr, errmsg = pcall (testgroup[testname])
  local elapse = clock() - start
  elapse = elapse < 2 and string.format ("%.2fms", elapse * 1000)
                       or string.format ("%.2fs", elapse)

  io.write (elapse)
  if noerr then
    print " ok"
  else
    print (" fail!\n", errmsg)
  end
  return noerr
end

local function run (tests)
  local testcount, testfail = 0, 0
  local elapse, start = 0
  for testname in pairs(tests) do
    start = clock()
    if not run_single (tests, testname) then testfail = testfail + 1 end
    elapse = clock() - start + elapse
    testcount = testcount + 1
    Sleep (sleep_delay)
  end
  elapse = elapse < 2 and string.format ("%.2fms", elapse * 1000)
                       or string.format ("%.2fs", elapse)

  print (string.format ("    %s --> %d out of %d test(s) failed.",
                        elapse, testfail, testcount))
end

local function delay (ms)
  sleep_delay = ms
end

return { run = run, run_single = run_single, test_delay = delay }
