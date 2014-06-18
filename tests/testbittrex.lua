require 'luarocks_path'
require 'pl.app'.require_here ".."
local utest = require 'unittest'
local pltest = require 'pl.test'
local dump = require 'pl.pretty'.dump

local keys = require 'tests.api_testkeys'.bittrex
local session = require 'exchange.bittrex' { key = keys.key, secret = keys.secret }
assert (session)

local make_retry = require 'tools.retry'
local session = make_retry (session, 3, "closed", "timeout")

local tests = 
{
  test_balance = function ()
    local r = session:balance ()

    dump (r)
    assert (r.AC > 0)
    assert (r.BTC)
  end,

  test_tradehistory = function ()
    local r = session:tradehistory ("BTC", "WC")

    dump (r)
  end,

  test_buy = function ()
    local r, errmsg = session:buy ("BTC", "LTC", 0.00015, 1)

    assert (not r and errmsg == "INSUFFICIENT_FUNDS")
  end,

  test_sell = function ()
    local r, errmsg = session:sell("BTC", "LTC", 0.15, 1)

    assert (not r and errmsg == "INSUFFICIENT_FUNDS")
  end,

  test_cancelorder = function ()
    local r, errmsg = session:cancelorder ("BTC", "LTC", 123)
    assert (not r and errmsg == "UUID_INVALID")
  end,

  test_openorders = function ()
    local r = session:openorders ("BTC", "LTC")

    dump (r)
  end,

  test_markethistory = function ()
    local r = session:markethistory ("BTC", "LTC")

    assert (r)
  end,

  test_orderbook = function ()
    local r = session:orderbook ("BTC", "LTC")

    assert (r.buy and r.sell)
    assert (r.buy.price and r.sell.price)
    assert (r.buy.amount and r.sell.amount)
  end,

  test_mixcasequery = function ()
    local r = session:orderbook ("BtC", "xmR")

    assert (r.buy and r.sell)
    assert (r.buy.price and r.sell.price)
    assert (r.buy.amount and r.sell.amount)
  end
}

utest.run (tests)
-- utest.run_single (tests, "test_openorders")
-- utest.run_single (tests, "test_orderbook")
