require 'pl.app'.require_here ".."
local utest = require 'tools.unittest'
local stack = require 'tools.simplestack'
local dump  = require 'pl.pretty'.dump
local tablex = require 'pl.tablex'

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
    assert (not publicapi.placeoffer)
    assert (not publicapi.canceloffer)
    assert (not publicapi.openoffers)
  end,

  test_lendingbook = function ()
    local r = assert (publicapi:lendingbook "BTC")
    
    local bottom_offer = #r
    assert (r)
    assert (r[1].rate < r[bottom_offer].rate)
    assert (r[1].rate > 0)
    assert (r[1].amount > 0)
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
    assert (type(r.asks.amount[1]) == 'number')
    assert (type(r.asks.price[1])  == 'number')
    assert (type(r.bids.amount[1]) == 'number')
    assert (type(r.bids.price[1])  == 'number')
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

local test_orders = stack ()
local test_offers = stack ()
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

    assert (type(r) == 'table')
    assert (#r > 0)
  end,

  test_buy = function ()
    local r, errmsg = tradeapi:buy ("BTC", "VTC", 0.00000015, 1000)

    assert (errmsg == "Not enough BTC." or (r and r.orderNumber), errmsg)
    if r then
      test_orders:push (assert (r.orderNumber))
    end
  end,

  test_sell = function ()
    local r, errmsg = tradeapi:sell ("USDT", "BTC", 40000, 0.000001)

    assert (errmsg == "Not enough BTC." or (r and r.orderNumber), errmsg)
    if r then 
      test_orders:push (assert (r.orderNumber))
    end
  end,

  test_badmoveorder = function ()
    local r, errmsg = tradeapi:moveorder ("BAD_ORDERNUMBER", 42000)

    assert (errmsg == "Invalid orderNumber parameter.", errmsg)
  end,
}

local lendapi = assert (publicapi.lendingapi (keys.key, keys.secret))
utest.group "poloniex_lendingapi"
{
  test_lendingapinames = function ()
    -- authenticated access should contain only lending functions
    assert (lendapi.balance)
    assert (lendapi.placeoffer)
    assert (lendapi.canceloffer)
    assert (lendapi.openoffers)
    assert (lendapi.activeoffers)
  end,

  test_placeoffer = function ()
    local r, errmsg = lendapi:placeoffer ("BTC", 0.02, 0.001, 3, false)

    assert (errmsg == "Amount must be at least 0.01." or (r and r.orderID), errmsg)
    if r then
      test_offers:push (assert (r.orderID))
    end
  end,

  test_lendingbalance = function ()
    local r = assert (lendapi:balance ())

    local k, v = next (r)
    assert (type(k) == 'string')
    assert (v + 0 > 0)
  end,

  test_activeoffersquery = function ()
    local r = assert (lendapi:activeoffers "BTC")
    assert (type(r) == 'table')
    if #r > 0 then
      assert (r[1].currency == "BTC")
      assert (r[1].amount + 0 > 0)
      assert (r[1].rate + 0 > 0)
    end
  end,
}

utest.group "poloniex_orderlist"
{
  test_openorders = function ()
    local r = assert (tradeapi:openorders ("USDT", "BTC"))

    assert (type(r) == 'table')
    assert (r[1] == nil or r[1].orderNumber)
  end,

  test_openoffers = function ()
    local r = assert (lendapi:openoffers "BTC")

    assert (type(r) == 'table')
    tablex.foreachi (r, function (n) assert (n.id) end)
  end,
}

utest.group "poloniex_cancels"
{
  test_cancelinvalidorder = function ()
    local r, errmsg = tradeapi:cancelorder ("BAD_ORDERNUMBER")
    assert (errmsg == "Invalid orderNumber parameter.", errmsg)
  end,

  test_cancelorder = function ()
    if test_orders:empty () then return end

    assert (not test_orders:empty (), "No test orders to cancel.")
    while not test_orders:empty () do
      r = assert (tradeapi:cancelorder (test_orders:top ()))
      assert (r.success == 1)
      test_orders:pop ()
    end
  end,

  test_cancelinvalidoffer = function ()
    local r, errmsg = lendapi:canceloffer ("BAD_OFFERERNUMBER")
    assert (errmsg == "Invalid orderNumber parameter.", errmsg)
  end,

  test_canceloffer = function ()
    if test_offers:empty () then return end

    assert (not test_offers:empty (), "No test offers to cancel.")
    while not test_offers:empty () do
      r = assert (lendapi:canceloffer (test_offers:top ()))
      assert (r.success == 1)
      test_offers:pop ()
    end
  end,
}

utest.run "poloniex_publicapi"
utest.run ("poloniex_tradingapi", 500) -- ms
utest.run ("poloniex_lendingapi", 500)
utest.run "poloniex_orderlist"
utest.run "poloniex_cancels"
