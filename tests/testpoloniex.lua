require 'luarocks_path'
require 'pl.app'.require_here ".."
local api = require 'exchange.poloniex'
local utest = require 'unittest'
local dump = require 'pl.pretty'.dump


local keys = require 'tests.api_testkeys'.poloniex
session = api { key = keys.key, secret = keys.secret }
assert (session)

local tests = 
{
  test_balance = function ()
    local r = session:balance()

    dump (r)
  end,

  test_tradehistory = function ()
    local r = session:tradehistory("BTC", "LTC")

    dump (r)
  end,

  test_buy = function ()
    local r = session:buy("BTC", "LTC", 0.00015, 1)

    dump (r)
  end,

  test_sell = function ()
    local r = session:sell("BTC", "LTC", 0.15, 1)

    dump (r)
  end,

  test_cancelorder = function ()
    local r = session:cancelorder("BTC", "LTC", 170675)

    dump (r)
  end,

  test_markethistory = function ()
    local r = session:markethistory("BTC", "LTC")

    assert (r)
  end,

  test_orderbook = function ()
    local r = session:orderbook("BTC", "LTC")

    dump (r)
  end,
  
  test_openorders = function ()
    local r = session:openorders("BTC", "CINNI")

    dump (r)
  end
}

utest.run (tests)
