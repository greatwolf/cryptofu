require 'pl.app'.require_here ".."
local utest = require 'tools.unittest'
local dump = require 'pl.pretty'.dump

local keys = require 'tests.api_testkeys'.poloniex
local publicapi = require 'exchange.poloniex'

utest.group "poloniex_publicapi"
{
  test_publicapinames = function()
    assert (publicapi.orderbook)
    assert (publicapi.markethistory)
    assert (publicapi.lendingbook)
    assert (publicapi.lendingapi)
    
    -- unauthenticated access should only contain public functions
    assert (not publicapi.buy)
    assert (not publicapi.sell)
    assert (not publicapi.cancelorder)
    assert (not publicapi.moveorder)
    assert (not publicapi.openorders)
    assert (not publicapi.tradehistory)
    assert (not publicapi.balance)
    assert (not publicapi.lendingoffer)
    assert (not publicapi.canceloffer)
    assert (not publicapi.openoffers)
  end,

  test_lendingbook = function ()
    local r = assert (publicapi:lendingbook "BTC")
    
    local bottom_offer = #r.offers
    assert (r.offers and r.demands)
    assert (r.offers[1].rate < r.offers[bottom_offer].rate)
  end,

  test_boguslendingbook = function ()
    local r, errmsg = publicapi:lendingbook "___"

    assert (not r and errmsg == "Invalid currency.", errmsg)
  end,

  test_bogusmarket = function ()
    local r, errmsg = publicapi:markethistory ("BTC", "___")

    assert (not r and errmsg == "Invalid currency pair.", errmsg)
  end,

  test_markethistory = function ()
    local r = publicapi:markethistory ("BTC", "LTC")

    assert (r and r[1])
    assert (r[1].date)
    assert (r[1].rate + 0 > 0)
    assert (r[1].amount + 0 > 0)
  end,

  test_orderbook = function ()
    local r = publicapi:orderbook ("BTC", "LTC")

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
    local r = publicapi:orderbook ("BtC", "xmR")

    assert (r.bids and r.asks)
    assert (r.asks.amount and r.bids.amount)
    assert (r.asks.price and r.bids.price)
  end
}

local make_retry = require 'tools.retry'
local tradeapi = assert (publicapi.tradingapi (keys.key, keys.secret))

local test_orders = {}
local test_offers = {}
utest.group "poloniex_tradingapi"
{
  test_tradingapinames = function()
    -- authenticated access should contain only trade functions
    assert (tradeapi.buy)
    assert (tradeapi.sell)
    assert (tradeapi.cancelorder)
    assert (tradeapi.moveorder)
    assert (tradeapi.openorders)
    assert (tradeapi.tradehistory)
    assert (tradeapi.balance)
  end,

  test_balance = function ()
    local r = assert (tradeapi:balance ())

    local k, v = next (r)
    assert (type(k) == 'string')
    assert (v + 0 > 0)
  end,

  test_tradehistory = function ()
    local r = assert (tradeapi:tradehistory ("BTC", "LTC"))

    assert (type(r) == "table")
    assert (#r > 0)
  end,

  test_buy = function ()
    local r = assert (tradeapi:buy ("BTC", "VTC", 0.00000015, 1000))

    table.insert (test_orders, assert (r.orderNumber))
  end,

  test_sell = function ()
    local r = assert (tradeapi:sell ("USDT", "BTC", 40000, 0.000001))

    table.insert (test_orders, assert (r.orderNumber))
  end,

  test_moveorder = function ()
    local test_order = tradeapi:sell ("USDT", "BTC", 41000, 0.000001)
    local r = assert (tradeapi:moveorder (test_order.orderNumber, 42000))

    table.insert (test_orders, r.orderNumber)
    assert (r.success == 1)
  end,
}

local lendapi = assert (publicapi.lendingapi (keys.key, keys.secret))
utest.group "poloniex_lendingapi"
{
  test_lendingapinames = function ()
    -- authenticated access should contain only lending functions
    assert (lendapi.balance)
    assert (lendapi.lendingoffer)
    assert (lendapi.canceloffer)
    assert (lendapi.openoffers)
  end,

  test_lendingoffer = function ()
    local r = assert (lendapi:lendingoffer ("BTC", 2.0, 0.001, 3, false))

    table.insert (test_offers, assert (r.orderID))
  end,

  test_lendingbalance = function ()
    local r = assert (lendapi:balance ())

    local k, v = next (r)
    assert (type(k) == 'string')
    assert (v + 0 > 0)
  end
}

utest.group "poloniex_orderlist"
{
  test_openorders = function ()
    local r = assert (tradeapi:openorders ("USDT", "BTC"))

    assert (type(r) == "table")
    assert (#r > 0)
    assert (r[1].orderNumber)
  end,

  test_openoffers = function ()
    local r = assert (lendapi:openoffers "BTC")

    assert (type(r) == "table")
    table.foreachi (r, function (_, n) assert (n.id) end)
  end,
}

utest.group "poloniex_cancels"
{
  test_cancelorder = function ()
    assert (#test_orders > 0, "No test orders to cancel.")
    local r
    for i = #test_orders, 1, -1 do
      r = assert (tradeapi:cancelorder (test_orders[i]))
      assert (r.success == 1)
      table.remove (test_orders)
    end
  end,

  test_canceloffer = function ()
    assert (#test_offers > 0, "No test offers to cancel.")
    local r
    for i = #test_offers, 1, -1 do
      r = assert (lendapi:canceloffer (test_offers[i]))
      assert (r.success == 1)
      table.remove (test_offers)
    end
  end,
}

utest.run "poloniex_publicapi"
utest.run ("poloniex_tradingapi", 500) -- ms
utest.run ("poloniex_lendingapi", 500)
utest.run "poloniex_orderlist"
utest.run "poloniex_cancels"
