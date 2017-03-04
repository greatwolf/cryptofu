require 'pl.app'.require_here ".."
local utest = require 'tools.unittest'
local dump = require 'pl.pretty'.dump

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
    -- dump(r)
    assert (#r > 0)
  end,

  test_markethistory = function ()
    local r = assert (publicapi:markethistory ("BTC", "LTC"))
    assert (#r > 0)
  end,

  test_bogusmarket = function ()
    local r, errmsg = publicapi:orderbook ("BTC", "___")
    assert (not r, r)
    assert (errmsg == "error 10020 symbol: invalid", errmsg)
  end,

  test_mixcasequery = function ()
    local r = assert (publicapi:markethistory ("BtC", "lTc"))
    assert (#r > 0)
  end,
}

local tradeapi = assert (publicapi.tradingapi (keys.key, keys.secret))

utest.group "bitfinex_tradingapi"
{
}

utest.run "bitfinex_publicapi"
utest.run "bitfinex_tradingapi"
