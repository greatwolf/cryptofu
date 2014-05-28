local function run_single (testgroup, testname)
  assert (testgroup[testname])
  io.write ("Running " .. testname .. "... ")
  local noerr, errmsg = pcall (testgroup[testname])
  if noerr then
    print "ok"
  else
    print ("fail!\n", errmsg)
  end
  return noerr
end

local function run (tests)
  local testcount, testfail = 0, 0
  local start = os.clock()
  for testname in pairs(tests) do
    if not run_single (tests, testname) then testfail = testfail + 1 end
    testcount = testcount + 1
  end
  local elapse = (os.clock() - start) * 1000 .. "ms"
  print ("", elapse, "--> " .. testfail .. " out of " .. testcount .. " test(s) failed.")
end

return { run = run, run_single = run_single }
