require 'pl.app'.require_here ".."
local utest   = require 'tools.unittest'
local stack   = require 'tools.simplestack'
local tablex  = require 'pl.tablex'


local keys      = require 'tests.api_testkeys'.bitfinex
local publicapi = require 'exchange.bitfinex'

-- UTC current time
local utcnow = function ()
  local now = os.date '!*t'
  now.isdst = nil
  return os.time (now)
end

utest.group "bitfinex_publicapi"
{
  test_publicapinames = function ()
    assert (publicapi.orderbook)
    assert (publicapi.markethistory)
    assert (publicapi.tradingapi)
    assert (publicapi.lendingbook)
    assert (publicapi.lendingapi)

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

    assert (not r and errmsg == "Unknown currency", errmsg)
  end,

  test_orderbook = function ()
    local r = assert (publicapi:orderbook ("BTC", "LTC"))
    assert (#r.asks > 0)
    assert (#r.bids > 0)
  end,

  test_markethistory = function ()
    local r = assert (publicapi:markethistory ("BTC", "LTC"))
    assert (r and #r > 0)
    tablex.foreachi (r, function (n)
                          assert (0 < n.date and n.date < utcnow (), n.date)
                          assert (n.rate > 0, n.rate)
                          assert (n.amount > 0, n.amount)
                        end)
  end,

  test_bogusmarket = function ()
    local r, errmsg = publicapi:orderbook ("BTC", "___")
    assert (not r and errmsg == "Unknown symbol", errmsg)
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
    local r = assert (tradeapi:balance ())

    assert (type(r) == 'table')
    tablex.foreach (r, function (v, k)
      assert (type(k) == 'string')
      assert (v >= 0)
    end)
  end,

  test_tradehistory = function ()
    local r = assert (tradeapi:tradehistory ("BTC", "USD"))

    assert (type(r) == 'table')
    tablex.foreachi (r, function (n)
                          assert (type(n.orderid) == 'string')
                          assert (0 < n.date and n.date < utcnow (), n.date)
                          assert (n.rate > 0, n.rate)
                          assert (n.amount > 0, n.amount)
                        end)
  end,

  test_buy = function ()
    local r, errmsg = tradeapi:buy ("BTC", "USD", 0.15, 1)

    assert ((r and r.orderid and r.side == "buy") or
            errmsg:match "Invalid order: not enough", errmsg)
    if r then
      test_orders:push (assert (r.orderid))
    end
  end,

  test_sell = function ()
    local r, errmsg = tradeapi:sell ("BTC", "USD", 10000.9, 0.01)

    assert ((r and r.orderid and r.side == "sell") or
            errmsg:match "Invalid order: not enough", errmsg)
    if r then
      test_orders:push (assert (r.orderid))
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
    local r, errmsg = lendapi:placeoffer ("BTC", 2.0, 0.001, 3)

    assert ((r and r.orderid) or
            errmsg:match "Invalid offer: not enough" or
            errmsg:match "Invalid offer: incorrect amount", errmsg)
    if r then
      test_offers:push (assert (r.orderid))
    end
  end,

  test_lendingbalance = function ()
    local r = assert (lendapi:balance ())

    -- balances should be in associative part of table
    assert (#r == 0)
    local isempty = true
    for k, v in pairs (r) do
      assert (type(k) == 'string')
      assert (v >= 0)
      isempty = false
    end
    assert (not isempty)
  end,

  test_activeoffersquery = function ()
    local r, errmsg = lendapi:activeoffers "BTC"

    assert (r and not errmsg, errmsg)
    assert (type(r) == 'table')
    tablex.foreachi (r, function (n)
                          assert (type(n.orderid) == 'string')
                          assert (n.currency == "BTC")
                          assert (0 < n.date and n.date < utcnow (), n.date)
                          assert (0.005 < n.rate and n.rate < 5.0, n.rate)
                          assert (n.amount > 0, n.amount)
                          assert (n.duration >= 2, n.duration)
                        end)
  end,
}

utest.group "bitfinex_orderlist"
{
  test_openorders = function ()
    local r = assert (tradeapi:openorders ("USD", "BTC"))

    assert (type(r) == 'table')
    tablex.foreachi (r, function (n)
                          assert (type(n.orderid) == 'string')
                          assert (n.side == "buy" or n.side == "sell")
                          assert (0 < n.date and n.date < utcnow (), n.date)
                          assert (n.rate > 0, n.rate)
                          assert (n.amount > 0, n.amount)
                        end)
  end,

  test_openoffers = function ()
    local r = assert (lendapi:openoffers "DSH")

    assert (type(r) == 'table')
    tablex.foreachi (r, function (n)
                          assert (type(n.orderid) == 'string')
                          assert (n.currency == "DSH")
                          assert (0 < n.date and n.date < utcnow (), n.date)
                          assert (0.005 < n.rate and n.rate < 5.0, n.rate)
                          assert (n.amount > 0, n.amount)
                          assert (n.duration >= 2, n.duration)
                        end)
  end,
}

utest.group "bitfinex_cancels"
{
  test_cancelbadorderidtype = function ()
    local ok, res = pcall (tradeapi.cancelorder, tradeapi, {"BAD_ORDERNUMBER"})
    assert (ok and res.result == "no valid order_ids given.", res.result)
  end,

  test_cancelinvalidorder = function ()
    local ok, res, errmsg = pcall (tradeapi.cancelorder, tradeapi, "42")
    assert (ok and res, res or errmsg)
    assert (res.result == "None to cancel", res.result)
  end,

  test_cancelorder = function ()
    if test_orders:empty () then return end

    assert (not test_orders:empty (), "No test orders to cancel.")

    local unpack = unpack or table.unpack
    r = assert (tradeapi:cancelorder (unpack (test_orders)))

    local cancelcount = r.result:match "All %((.-)%) submitted for cancellation;"
    assert (cancelcount, r.result)
    assert (tonumber (cancelcount) == test_orders:size ())
    test_orders:clear ()
  end,

  test_cancelinvalidoffer = function ()
    local r, errmsg = lendapi:canceloffer ("BAD_OFFERERNUMBER")
    assert (errmsg:match "offer_id should be an integer", errmsg)
  end,

  test_canceloffer = function ()
    if test_offers:empty () then return end

    assert (not test_offers:empty (), "No test offers to cancel.")
    while not test_offers:empty () do
      local top = test_offers:top ()
      r = assert (lendapi:canceloffer (top))
      assert (r.success == 1)
      test_offers:pop ()
    end
  end,
}

utest.run "bitfinex_publicapi"
utest.run "bitfinex_tradingapi"
utest.run "bitfinex_lendingapi"
utest.run "bitfinex_orderlist"
utest.run "bitfinex_cancels"
