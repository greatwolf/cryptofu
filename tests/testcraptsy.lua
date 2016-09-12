require 'pl.app'.require_here ".."
local utest = require 'unittest'
local dump = require 'pl.pretty'.dump

local keys = require 'tests.api_testkeys'.craptsy
local session = require 'exchange.craptsy' { key = keys.key, secret = keys.secret }
assert (session)

local make_retry = require 'tools.retry'
local session = make_retry (session, 3, "closed", "timeout")

utest.group "craptsy_pubapi"
{
  test_markethistory = function ()
    local r = assert (session:markethistory ("BTC", "LTC"))

    assert (r)
  end,

  test_orderbook = function ()
    local r = session:orderbook ("BTC", "LTC")

    assert (r.buy and r.sell)
    assert (r.buy.price and r.sell.price)
    assert (r.buy.amount and r.sell.amount)
  end,

  test_mixcasequery = function ()
    local r = session:orderbook ("BtC", "vtC")

    assert (r.buy and r.sell)
    assert (r.buy.price and r.sell.price)
    assert (r.buy.amount and r.sell.amount)
  end
}

utest.group "craptsy_privapi"
{
  test_balance = function ()
    local r = session:balance ()

    dump (r)
    assert (r.BTC)
  end,

  test_tradehistory = function ()
    local r = session:tradehistory ("BTC", "MZC")

    dump (r)
    assert (r)
  end,

  test_buy = function ()
    local r, errmsg = session:buy ("BTC", "LTC", 0.00015, 1)

    assert (not r and errmsg == "Insufficient BTC in account to complete this order.")
  end,

  test_sell = function ()
    local r, errmsg = assert (session:sell("lTC", "FLAP", 0.15, 4.2))

    dump (r)
    assert (r.orderNumber)
  end,

  test_cancelorder = function ()
    local orders = session:openorders ("LTC", "FLAP")
    for _, order in ipairs (orders) do
      assert (session:cancelorder ("LTC", "FLAP", order.orderid))
    end
  end,

  test_cancelbadordernumber = function ()
    local r, errmsg = session:cancelorder ("BTC", "VTC", 1337)

    assert (not r and errmsg == "Order not found.")
  end,

  test_openorders = function ()
    local r = session:openorders ("lTC", "FLAP")

    dump (r)
    assert (r)
  end,
}

utest.run "craptsy_pubapi"
utest.run "craptsy_privapi"
