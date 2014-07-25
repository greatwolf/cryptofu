require 'luarocks_path'
require 'pl.app'.require_here ".."
local utest = require 'unittest'
local pltest = require 'pl.test'
local dump = require 'pl.pretty'.dump

local keys = require 'tests.api_testkeys'.poloniex
local session = require 'exchange.poloniex' { key = keys.key, secret = keys.secret }
assert (session)

local make_retry = require 'tools.retry'
session = make_retry (session, 3, "closed", "timeout")

utest.group "poloniex_pubapi"
{
  test_bogusmarket = function ()
    local r, errmsg = session:markethistory ("BTC", "MRO")

    assert (not r and errmsg == "Invalid currency pair.", errmsg)
  end,

  test_markethistory = function ()
    local r = session:markethistory ("BTC", "LTC")

    assert (r)
  end,

  test_orderbook = function ()
    local r = session:orderbook ("BTC", "LTC")

    assert (r.sell.amount and r.buy.amount)
    assert (r.sell.price and r.buy.price)
  end,

  test_mixcasequery = function ()
    local r = session:orderbook ("BtC", "xmR")

    assert (r.buy and r.sell)
    assert (r.sell.amount and r.buy.amount)
    assert (r.sell.price and r.buy.price)
  end
}

local test_orders = {}
local poloniex_privapi = utest.group "poloniex_privapi"
{
  test_balance = function ()
    local r = session:balance ()

    dump (r)
    assert (r.BTC > 0)
  end,

  test_tradehistory = function ()
    local r = session:tradehistory ("BTC", "LTC")

    dump (r)
  end,

  test_openorders = function ()
    local r = session:openorders ("BTC", "VTC")

    dump (r)
  end,

  test_buy = function ()
    local r, errmsg = assert (session:buy ("BTC", "VTC", 0.000015, 10))

    dump (r)
    table.insert (test_orders, assert (r.orderNumber))
  end,

  test_sell = function ()
    local r, errmsg = assert (session:sell ("BTC", "VTC", 0.15, 0.01))

    dump (r)
    table.insert (test_orders, assert (r.orderNumber))
  end,

  test_cancelorder = function ()
    for i = #test_orders, 1, -1 do
      assert (session:cancelorder ("BTC", "VTC", test_orders[i]))
      table.remove (test_orders)
    end
  end,
}

utest.run "poloniex_pubapi"
utest.run ("poloniex_privapi", 500) -- ms
utest.run_single (poloniex_privapi, "test_cancelorder")
