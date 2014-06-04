local clock = os.clock
local print, pcall = print, pcall

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
  local start = clock()
  for testname in pairs(tests) do
    if not run_single (tests, testname) then testfail = testfail + 1 end
    testcount = testcount + 1
  end
  local elapse = clock() - start
  elapse = elapse < 2 and string.format ("%.2fms", elapse * 1000)
                       or string.format ("%.2fs", elapse)

  print (string.format ("    %s --> %d out of %d test(s) failed.",
                        elapse, testfail, testcount))
end

return { run = run, run_single = run_single }
