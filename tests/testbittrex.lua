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
  end,

  test_tradehistory = function ()
    local r = session:tradehistory ("BTC", "WC")

    dump (r)
  end,

  test_buy = function ()
    local r = session:buy ("BTC", "LTC", 0.00015, 1)

    assert (r.message == "INSUFFICIENT_FUNDS", r.message)
    dump (r)
  end,

  test_sell = function ()
    local r = session:sell("BTC", "LTC", 0.15, 1)

    assert (r.message == "INSUFFICIENT_FUNDS", r.message)
    dump (r)
  end,

  -- test_cancelorder = function ()
    -- local orders = session:openorders ("BTC", "LTC")
    -- for _, order in ipairs (orders) do
      -- local r = session:cancelorder ("BTC", "LTC", order.orderNumber)
      -- dump (r)
    -- end
  -- end,

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

    dump (r)
    assert (r.buy and r.sell)
  end,

  test_mixcasequery = function ()
    local r = session:orderbook ("BtC", "xmR")

    dump (r)
    assert (r.buy and r.sell)
  end
}

utest.run (tests)
-- utest.run_single (tests, "test_openorders")
-- utest.run_single (tests, "test_orderbook")
