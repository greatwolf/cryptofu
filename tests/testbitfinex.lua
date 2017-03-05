require 'pl.app'.require_here ".."
local utest   = require 'tools.unittest'
local stack   = require 'tools.simplestack'
local tablex  = require 'pl.tablex'


local keys      = require 'tests.api_testkeys'.bitfinex
local publicapi = require 'exchange.bitfinex'

utest.group "bitfinex_publicapi"
{
  test_publicapinames = function ()
    assert (publicapi.orderbook)
    assert (publicapi.markethistory)

    -- unauthenticated access should only contain public functions
    assert (not publicapi.buy)
    assert (not publicapi.sell)
    assert (not publicapi.cancelorder)
    assert (not publicapi.openorders)
    assert (not publicapi.tradehistory)
    assert (not publicapi.balance)
    assert (not publicapi.placeoffer)
    assert (not publicapi.canceloffer)
    assert (not publicapi.openoffers)
  end,

  test_orderbook = function ()
    local r = assert (publicapi:orderbook ("BTC", "LTC"))
    assert (#r.asks > 0)
    assert (#r.bids > 0)
  end,

  test_markethistory = function ()
    local r = assert (publicapi:markethistory ("BTC", "LTC"))
    assert (#r > 0)
  end,

  test_bogusmarket = function ()
    local r, errmsg = publicapi:orderbook ("BTC", "___")
    assert (type(r) == 'table', r)
    assert (r.message == "Unknown symbol", r.message)
  end,

  test_mixcasequery = function ()
    local r = assert (publicapi:markethistory ("BtC", "lTc"))
    assert (#r > 0)
  end,
}

local tradeapi = assert (publicapi.tradingapi (keys.key, keys.secret))

local test_orders = stack ()
utest.group "bitfinex_tradingapi"
{
  test_tradingapinames = function()
    assert (not tradeapi.orderbook)
    assert (not tradeapi.markethistory)

    -- authenticated access should contain only trade functions
    assert (tradeapi.buy)
    assert (tradeapi.sell)
    assert (tradeapi.cancelorder)
    assert (tradeapi.openorders)
    assert (tradeapi.tradehistory)
    assert (tradeapi.balance)
  end,

  test_balance = function ()
    local r, errmsg = assert (tradeapi:balance ())

    assert (#r > 0)
    local _, v = next (r)
    assert (type(v.type)     == 'string')
    assert (type(v.currency) == 'string')
    assert (v.amount and v.available)
    assert (not (v.amount + v.available < 0))
  end,

  test_tradehistory = function ()
    local r = assert (tradeapi:tradehistory ("BTC", "LTC"))

    assert (type(r) == 'table')
  end,

  test_buy = function ()
    local r, errmsg = tradeapi:buy ("BTC", "USD", 0.15, 1)

    assert (r.order_id, errmsg or r)
    assert (r.side == "buy")
    if r then
      test_orders:push (assert (r.order_id))
    end
  end,

  test_sell = function ()
    local r, errmsg = tradeapi:sell ("BTC", "USD", 10000.9, 0.01)

    assert (r.order_id, errmsg or r)
    assert (r.side == "sell")
    if r then
      test_orders:push (assert (r.order_id))
    end
  end,
}

utest.group "bitfinex_orderlist"
{
  test_openorders = function ()
    local r = assert (tradeapi:openorders ("USD", "BTC"))

    assert (type(r) == 'table')
    tablex.foreachi (r, function (v)
                          assert (type(v.id) == 'number')
                          assert (v.side == "buy" or v.side == "sell")
                          assert (v.price)
                          assert (v.original_amount)
                        end)
  end,
}

utest.group "bitfinex_cancels"
{
  test_cancelbadorderid = function ()
    local ok, res = pcall (tradeapi.cancelorder, tradeapi, "BAD_ORDERNUMBER")
    assert (not ok and res:match "no valid orderids to cancel!", res)
  end,

  test_cancelinvalidorder = function ()
    local ok, res = pcall (tradeapi.cancelorder, tradeapi, 42)
    assert (ok and res.result == "None to cancel", res)
  end,

  test_cancelorder = function ()
    if test_orders:empty () then return end

    assert (not test_orders:empty (), "No test orders to cancel.")

    local unpack = unpack or table.unpack
    r = assert (tradeapi:cancelorder (unpack (test_orders)))

    local cancelcount = r.result:match "All %((.-)%) submitted for cancellation;"
    assert (tonumber (cancelcount) == test_orders:size ())
    test_orders:clear ()
  end,
}

utest.run "bitfinex_publicapi"
utest.run "bitfinex_tradingapi"
utest.run "bitfinex_orderlist"
utest.run "bitfinex_cancels"
