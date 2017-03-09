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

    assert (type(r) == 'table')
    assert (#r > 0)
    tablex.foreachi (r, function (v)
      assert (type(v.type) == 'string')
      assert (v.type == "exchange")
      assert (type(v.currency) == 'string')
      assert (v.amount and v.available)
      assert (not (v.amount + v.available < 0))
    end)
  end,

  test_tradehistory = function ()
    local r = assert (tradeapi:tradehistory ("BTC", "LTC"))

    assert (type(r) == 'table')
  end,

  test_buy = function ()
    local r, errmsg = tradeapi:buy ("BTC", "USD", 0.15, 1)

    assert (not errmsg and r, errmsg or r)
    assert (r.order_id and r.side == "buy")
    if r then
      test_orders:push (assert (r.order_id))
    end
  end,

  test_sell = function ()
    local r, errmsg = tradeapi:sell ("BTC", "USD", 10000.9, 0.01)

    assert (not errmsg and r, errmsg or r)
    assert (r.order_id and r.side == "sell")
    if r then
      test_orders:push (assert (r.order_id))
    end
  end,
}

local lendapi = assert (publicapi.lendingapi (keys.key, keys.secret))
local test_offers = stack ()
utest.group "bitfinex_lendingapi"
{
  test_lendingapinames = function ()
    assert (not lendapi.orderbook)
    assert (not lendapi.markethistory)
    assert (not lendapi.buy)
    assert (not lendapi.sell)
    assert (not lendapi.cancelorder)
    assert (not lendapi.openorders)
    assert (not lendapi.tradehistory)

    -- authenticated access should contain only lending functions
    assert (lendapi.balance)
    assert (lendapi.placeoffer)
    assert (lendapi.canceloffer)
    assert (lendapi.openoffers)
    assert (lendapi.activeoffers)
  end,

  test_placeoffer = function ()
    local r, errmsg = lendapi:placeoffer ("BTC", 0.02, 0.001, 3)

    assert (errmsg:match "Invalid offer: incorrect amount" or (r and r.offer_id), errmsg)
    if r then
      test_offers:push (assert (r.offer_id))
    end
  end,

  test_lendingbalance = function ()
    local r, errmsg = assert (lendapi:balance ())

    assert (type(r) == 'table')
    assert (#r > 0)
    tablex.foreachi (r, function (v)
      assert (type(v.type) == 'string')
      assert (v.type == "deposit")
      assert (type(v.currency) == 'string')
      assert (v.amount and v.available)
      assert (not (v.amount + v.available < 0))
    end)
  end,

  test_activeoffersquery = function ()
    local r, errmsg = lendapi:activeoffers "BTC"

    assert (r and not errmsg, errmsg)
    assert (type(r) == 'table')
    if #r > 0 then
      assert (r[1].currency == "BTC")
      assert (r[1].amount + 0 > 0)
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

  test_openoffers = function ()
    local r = assert (lendapi:openoffers "USD")

    assert (type(r) == 'table')
    tablex.foreachi (r, function (n) assert (n.id and n.currency == "USD") end)
  end,
}

utest.group "bitfinex_cancels"
{
  test_cancelbadorderid = function ()
    local ok, res = pcall (tradeapi.cancelorder, tradeapi, "BAD_ORDERNUMBER")
    assert (ok and res.result == "no valid order_ids given.", res)
  end,

  test_cancelinvalidorder = function ()
    local ok, res, errmsg = pcall (tradeapi.cancelorder, tradeapi, 42)
    assert (ok and res, res or errmsg)
    assert (res.result == "None to cancel")
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
utest.run "bitfinex_lendingapi"
utest.run "bitfinex_orderlist"
utest.run "bitfinex_cancels"
