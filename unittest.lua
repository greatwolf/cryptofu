local ffi = require 'ffi'
local clock = os.clock
local print, pcall = print, pcall
ffi.cdef [[void Sleep (int ms);]]
local Sleep = ffi.C.Sleep

local test_harness = {}
local test_report = {}
local function group (groupname)
  return function (t)
    test_harness[groupname] = t
    return t
  end
end

local function run_single (testgroup, testname)
  assert (testgroup[testname])
  io.write ("  Running " .. testname .. "... ")
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

local function run (testgroup_name, delay)
  local testcount, testfail = 0, 0
  local elapse, start = 0
  print (string.format ("Testing %s:", testgroup_name))
  local testgroup = test_harness[testgroup_name]
  for testname in pairs(testgroup) do
    start = clock()
    if not run_single (testgroup, testname) then testfail = testfail + 1 end
    elapse = clock() - start + elapse
    testcount = testcount + 1
    Sleep (delay or 0)
  end
  elapse = elapse < 2 and string.format ("%.2fms", elapse * 1000)
                       or string.format ("%.2fs", elapse)

  local result = string.format ("  %16s --> %d Passed, %d Failed, Total %d, %s",
                                testgroup_name, testcount - testfail, testfail, testcount, elapse)
  table.insert (test_report, result)
end

local utest = newproxy (true)
local mt = getmetatable (utest)
mt.__index = { group = group, run = run, run_single = run_single, }
mt.__gc = function (self)
  print ("\nTest Report:")
  print (("-"):rep (80))
  for _, each in ipairs (test_report) do
    print (each)
  end
end

return utest
