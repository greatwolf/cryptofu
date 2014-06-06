require 'luarocks_path'
require 'pl.app'.require_here ".."
local utest = require 'unittest'
local pltest = require 'pl.test'
local dump = require 'pl.pretty'.dump

local keys = require 'tests.api_testkeys'.poloniex
local session = require 'exchange.poloniex' { key = keys.key, secret = keys.secret }
assert (session)

local create_retry = require 'util'.create_retry
local retry = create_retry
{
  "closed",
  "timeout",
  attempts = 3
}

local tests = 
{
  test_balance = function ()
    local r = retry (session.balance, session)

    dump (r)
  end,

  test_tradehistory = function ()
    local r = retry (session.tradehistory, session, "BTC", "LTC")

    dump (r)
  end,

  test_buy = function ()
    local r = retry (session.buy, session, "BTC", "LTC", 0.00015, 1)

    dump (r)
  end,

  test_sell = function ()
    local r = pltest.assertraise (function()
      session:sell("BTC", "LTC", 0.15, 1)
    end, "Not enough LTC.")
  end,

  test_cancelorder = function ()
    local orders = retry (session.openorders, session, "BTC", "LTC")
    for _, order in ipairs (orders) do
      local r = retry (session.cancelorder, session, "BTC", "LTC", order.orderNumber)
      dump (r)
    end
  end,

  test_markethistory = function ()
    local r = retry (session.markethistory, session, "BTC", "LTC")

    assert (r)
  end,

  test_orderbook = function ()
    local r = retry (session.orderbook, session, "BTC", "LTC")

    dump (r)
  end,
  
  test_openorders = function ()
    local r = retry (session.openorders, session, "BTC", "LTC")

    dump (r)
  end,

  test_mixcasequery = function ()
    local r = retry (session.orderbook, session, "BtC", "xmR")

    dump (r)
    assert (r.buy and r.sell)
  end
}

utest.run (tests)
-- utest.run_single (tests, "test_openorders")
-- utest.run_single (tests, "test_orderbook")
