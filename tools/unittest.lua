local sleep = require 'tools.sleep'
local clock = os.clock
local print, pcall = print, pcall

local function pretty_timer (ms)
  return ms < 2 and string.format ("%.2f msecs", ms * 1000)
                 or string.format ("%.2f secs", ms)
end

local test_harness = {}
local test_report = { totalcount = 0, totalfail = 0, totalelapse = 0 }
local function group (groupname)
  return function (t)
    test_harness[groupname] = t
    return t
  end
end

local function run_single (testgroup, testname)
  assert (testgroup[testname])
  io.write (string.format ("  Running %-48s", testname .. "... "))
  local start = clock()
  local noerr, errmsg = pcall (testgroup[testname])
  local elapse = clock() - start
  elapse = pretty_timer (elapse)

  io.write (string.format ("[%s] %s\n", noerr and "pass" or "failed", elapse))
  if not noerr then
    print ('\n', errmsg, '\n')
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
    sleep (delay or 0)
  end

  local result = string.format ("  %-24s --> %3d Passed, %3d Failed, Total %3d, %s",
                                testgroup_name, testcount - testfail, testfail, testcount, pretty_timer (elapse))
  table.insert (test_report, result)
  test_report.totalcount  = test_report.totalcount + testcount
  test_report.totalfail   = test_report.totalfail + testfail
  test_report.totalelapse = test_report.totalelapse + elapse
end

-- lua 5.2+ supports __gc for tables but must be non-nil when
-- setting mt otherwise it won't be marked for finalization
local utest = newproxy and newproxy (true) or setmetatable ({}, { __gc = true })
local mt = getmetatable (utest)
mt.__index = { group = group, run = run, run_single = run_single, }
mt.__gc = function (self)
  print ("\nHarness Summary:")
  print (("-"):rep (80))
  table.foreachi (test_report, function (_, v) print (v) end)

  local fail, count = test_report.totalfail, test_report.totalcount
  local elapse      = test_report.totalelapse
  io.write ((" "):rep (27), ("="):rep (53))
  io.write ((" "):rep (31), string.format ("%3d Passed, %3d Failed, Total %3d, %s",
                                           count - fail, fail, count, pretty_timer (elapse)))

  if fail > 0 then os.exit (fail) end
end

return utest
