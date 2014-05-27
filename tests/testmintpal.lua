require 'luarocks_path'
require 'pl.app'.require_here ".."
local api = require 'exchange.mintpal'
local d = require 'pl.pretty'.dump
dump = function (t) return d (t) end

local mintpal_cookies = require 'tests.api_testkeys'.mintpal

session = api (mintpal_cookies)
assert (session)

local tests = 
{
  test_balance = function ()
    local r, err = session:balance()

    dump (r)
  end,

  test_tradehistory = function ()
    local r = session:tradehistory("BTC", "LTC")

    dump (r)
  end,

  test_buy = function ()
    local r, err = session:buy("BTC", "LTC", 0.00015, 1.001)

    dump (r)
  end,

  test_sell = function ()
    local r = session:sell("BTC", "AC", 0.015, 1)

    dump (r)
  end,

  test_cancelorder = function ()
    local orders = session:openorders ("BTC", "LTC")
    for _, each in ipairs (orders.data) do
      dump (session:cancelorder("BTC", "LTC", each.order_id))
    end
    
    orders = session:openorders ("BTC", "AC")
    for _, each in ipairs (orders.data) do
      dump (session:cancelorder("BTC", "AC", each.order_id))
    end
  end,

  test_markethistory = function ()
    local r = session:markethistory("BTC", "LTC")

    assert (next(r))
  end,

  test_orderbook = function ()
    local r = session:orderbook("BTC", "LTC")

    assert (next(r))
  end,
  
  test_openorders = function ()
    dump (session:openorders("BTC", "LTC"))
    dump (session:openorders("BTC", "AC"))
    dump (session:openorders("BTC", "BC"))
  end
}

function run_single (testname, test)
  io.write ("Running " .. testname .. "... ")
  local noerr, errmsg = pcall (test)
  if noerr then
    print "ok"
  else
    print ("fail!\n", errmsg)
  end
  return noerr
end

function run_tests (tests)
  local testcount, testfail = 0, 0
  for testname, test in pairs(tests) do
    if not run_single (testname, test) then testfail = testfail + 1 end
    testcount = testcount + 1
  end
  print ("  --> " .. testfail .. " out of " .. testcount .. " test(s) failed.")
end

run_tests (tests)
-- run_single ("test_balance", tests.test_balance)
-- run_single ("test_buy", tests.test_buy)
-- run_single ("test_sell", tests.test_sell)
-- run_single ("test_openorders", tests.test_openorders)
-- run_single ("test_cancelorder", tests.test_cancelorder)
