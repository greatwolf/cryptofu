require 'pl.app'.require_here ".."
local utest = require 'tools.unittest'
local stack = require 'tools.simplestack'
local pltest = require 'pl.test'
local dump = require 'pl.pretty'.dump

local keys = require 'tests.api_testkeys'.bittrex
local session = require 'exchange.bittrex' { key = keys.key, secret = keys.secret }
assert (session)

local make_retry = require 'tools.retry'
session = make_retry (session, 3, "closed", "timeout")

utest.group "bittrex_publicapi"
{
  test_bogusmarket = function ()
    local r, errmsg = session:markethistory ("BTC", "___")

    assert (not r and errmsg == "INVALID_MARKET", errmsg)
  end,

  test_markethistory = function ()
    local r = assert (session:markethistory ("BTC", "LTC"))
    
    assert (#r > 0)
  end,

  test_orderbook = function ()
    local r = session:orderbook ("BTC", "LTC")

    assert (r.bids and r.asks)
    assert (r.bids.price and r.asks.price)
    assert (r.bids.amount and r.asks.amount)
    assert (r.bids.price[1] < r.asks.price[1])
    assert (type(r.asks.amount[1]) == 'number')
    assert (type(r.asks.price[1])  == 'number')
    assert (type(r.bids.amount[1]) == 'number')
    assert (type(r.bids.price[1])  == 'number')
  end,

  test_mixcasequery = function ()
    local r = session:orderbook ("BtC", "xmR")

    assert (r.bids and r.asks)
    assert (r.bids.price and r.asks.price)
    assert (r.bids.amount and r.asks.amount)
  end
}

local test_orders = stack ()
utest.group "bittrex_tradingapi"
{
  test_balance = function ()
    local r = assert (session:balance ())

    assert (r.BTC and type (r.BTC) == 'number')
  end,

  test_tradehistory = function ()
    local r = assert (session:tradehistory ("BTC", "VTC"))
  end,

  test_buy = function ()
    local r, errmsg = session:buy ("BTC", "LTC", 0.000015, 34)

    assert (errmsg == "INSUFFICIENT_FUNDS" or (r and r.orderNumber), errmsg)
    test_orders:push (r and r.orderNumber)
  end,

  test_sell = function ()
    local r, errmsg = assert (session:sell("BTC", "VTC", 1.5, 0.01))

    assert (errmsg == "INSUFFICIENT_FUNDS" or (r and r.orderNumber), errmsg)
    test_orders:push (r and r.orderNumber)
  end,
}

utest.group "bittrex_orderlist"
{
  test_openorders = function ()
    local r = assert (session:openorders ("BTC", "VTC"))

    assert (type(r) == 'table')
    assert (#r > 0)
  end,
}

utest.group "bittrex_cancels"
{
  test_cancelorder = function ()
    while not test_orders:empty () do
      assert (session:cancelorder ("BTC", "VTC", test_orders:top ()))
      test_orders:pop ()
    end
  end,
}

utest.run "bittrex_pubapi"
utest.run ("bittrex_privapi", 400) -- ms
utest.run "bittrex_orderlist"
utest.run "bittrex_cancels"
