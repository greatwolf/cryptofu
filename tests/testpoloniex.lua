require 'pl.app'.require_here ".."
local utest = require 'tools.unittest'
local pltest = require 'pl.test'
local dump = require 'pl.pretty'.dump

local keys = require 'tests.api_testkeys'.poloniex
local pubapi = require 'exchange.poloniex'

utest.group "poloniex_pubapi"
{
  test_pubapinames = function()
    assert (pubapi.orderbook)
    assert (pubapi.markethistory)
    assert (pubapi.lendingbook)
    
    -- unauthenticated access should only contain public functions
    assert (not pubapi.buy)
    assert (not pubapi.sell)
    assert (not pubapi.cancelorder)
    assert (not pubapi.moveorder)
    assert (not pubapi.openorders)
    assert (not pubapi.tradehistory)
    assert (not pubapi.balance)
  end,

  test_lendingbook = function ()
    local r = assert (pubapi:lendingbook "BTC")
    
    local bottom_offer = #r.offers
    assert (r.offers and r.demands)
    assert (r.offers[1].rate < r.offers[bottom_offer].rate)
  end,

  test_boguslendingbook = function ()
    local r, errmsg = pubapi:lendingbook "___"

    assert (not r and errmsg == "Invalid currency.", errmsg)
  end,

  test_bogusmarket = function ()
    local r, errmsg = pubapi:markethistory ("BTC", "___")

    assert (not r and errmsg == "Invalid currency pair.", errmsg)
  end,

  test_markethistory = function ()
    local r = pubapi:markethistory ("BTC", "LTC")

    assert (r)
  end,

  test_orderbook = function ()
    local r = pubapi:orderbook ("BTC", "LTC")

    assert (r.bids and r.asks)
    assert (r.asks.amount and r.bids.amount)
    assert (r.asks.price and r.bids.price)
    assert (r.bids.price[1] < r.asks.price[1])
    assert (type(r.asks.amount[1]) == "number")
    assert (type(r.asks.price[1])  == "number")
    assert (type(r.bids.amount[1]) == "number")
    assert (type(r.bids.price[1])  == "number")
  end,

  test_mixcasequery = function ()
    local r = pubapi:orderbook ("BtC", "xmR")

    assert (r.bids and r.asks)
    assert (r.asks.amount and r.bids.amount)
    assert (r.asks.price and r.bids.price)
  end
}

local make_retry = require 'tools.retry'
local session = assert (pubapi { key = keys.key, secret = keys.secret })
session = make_retry (session, 3, "closed", "timeout")

local test_orders = {}
local poloniex_privapi = utest.group "poloniex_privapi"
{
  test_privapinames = function()
    -- authenticated access should contain all functions
    assert (session.orderbook)
    assert (session.markethistory)
    assert (session.lendingbook)

    assert (session.buy)
    assert (session.sell)
    assert (session.cancelorder)
    assert (session.openorders)
    assert (session.tradehistory)
    assert (session.balance)
  end,

  test_balance = function ()
    local r = assert (session:balance ())

    assert (r.BTC and type(r.BTC) == "number")
  end,

  test_tradehistory = function ()
    local r = assert (session:tradehistory ("BTC", "LTC"))

    assert (type(r) == "table")
    assert (#r > 0)
  end,

  test_buy = function ()
    local r, errmsg = assert (session:buy ("BTC", "VTC", 0.00000015, 1000))

    table.insert (test_orders, assert (r.orderNumber))
  end,

  test_sell = function ()
    local r, errmsg = assert (session:sell ("USDT", "BTC", 40000, 0.000001))

    table.insert (test_orders, assert (r.orderNumber))
  end,
}

utest.group "poloniex_orderlist"
{
  test_openorders = function ()
    local r = assert (session:openorders ("USDT", "BTC"))

    assert (type(r) == "table")
    assert (#r > 0)
  end,
}

utest.group "poloniex_cancels"
{
  test_cancelorder = function ()
    local r
    for i = #test_orders, 1, -1 do
      r = assert (session:cancelorder ("BTC", "VTC", test_orders[i]))
      assert (r.success == 1)
      table.remove (test_orders)
    end
  end,
}

utest.run "poloniex_pubapi"
utest.run ("poloniex_privapi", 500) -- ms
utest.run "poloniex_orderlist"
utest.run "poloniex_cancels"
