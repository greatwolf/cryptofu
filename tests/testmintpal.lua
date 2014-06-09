require 'luarocks_path'
require 'pl.app'.require_here ".."
local utest = require 'unittest'
local d = require 'pl.pretty'.dump
dump = function (t) return d (t) end

local mintpal_cookies = require 'tests.api_testkeys'.mintpal

local session = require 'exchange.mintpal' (mintpal_cookies)
assert (session)

local make_retry = require 'tools.retry'
local session = make_retry (session, 20, "timeout", "response not from MintPal!")

local tests = 
{
  test_balance = function ()
    local r = session:balance ()

    dump (r)
  end,

  test_tradehistory = function ()
    local r = session:tradehistory ("BTC", "LTC")

    dump (r)
  end,

  test_buy = function ()
    local r = session:buy ("BTC", "LTC", 0.00015, 1.001)

    dump (r)
  end,

  test_sell = function ()
    local r = session:sell ("BTC", "AC", 0.015, 1)

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
    local r = session:markethistory ("BTC", "LTC")

    assert (next(r))
  end,

  test_orderbook = function ()
    local r = session:orderbook ("BTC", "LTC")

    dump (r)
    assert (next(r))
  end,
  
  test_openorders = function ()
    dump (session:openorders("BTC", "LTC"))
    dump (session:openorders("BTC", "AC"))
    dump (session:openorders("BTC", "BC"))
  end,

  test_mixcasequery = function ()
    local r = session:orderbook ("BtC", "caiX")

    dump (r)
    assert (next(r))
  end
}

utest.run (tests)
-- utest.run_single (tests, "test_orderbook")
