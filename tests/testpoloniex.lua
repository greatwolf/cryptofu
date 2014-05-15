require 'luarocks_path'
require 'pl.app'.require_here ".."
local api = require 'poloniex'
local dump = require 'pl.pretty'.dump

local apikey = "89QK21JO-8O72SN4U-ZUR4CGE5-TSGNT63S"
local apisecret = "50c94254737f8a47364eb6825055fd93c5cf9b2e927d366e7acdf22e58e89e3fa2c32955d1feddc2f395a2d44507c36167be348dbd44b3eae6d1019d938994cd"
session = api { key = apikey, secret = apisecret }

local tests = 
{
  test_balance = function ()
    local r = session:balance()

    assert (r.BTC == "0.0")
    assert (r.LTC == "0.0")
    assert (r.DRK == "0.0")
  end,

  test_tradehistory = function ()
    local r = session:tradehistory("BTC", "LTC")

    assert (not r)
  end,

  test_buy = function ()
    local r = session:buy("BTC", "LTC", 0.00015, 1)

    assert (r.error == "Not enough BTC.")
  end,

  test_sell = function ()
    local r = session:sell("BTC", "LTC", 0.15, 1)

    assert (r.error == "Not enough LTC.")
  end,

  test_cancelorder = function ()
    local r = session:cancelorder("BTC", "LTC", 170675)

    assert (r.error:match "Invalid order number")
  end,

  test_markethistory = function ()
    local r = session:markethistory("BTC", "LTC")

    -- dump (r)
    assert (next(r))
  end,

  test_orderbook = function ()
    local r = session:orderbook("BTC", "LTC")

    assert (next(r))
  end,
  
  test_openorders = function ()
    local r = session:openorders("BTC", "LTC")
    assert (not r)
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

-- run_tests (tests)
run_single ("test_cancelorder", tests.test_cancelorder)
