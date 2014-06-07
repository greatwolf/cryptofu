require 'luarocks_path'
require 'pl.app'.require_here ".."
local utest = require 'unittest'
local d = require 'pl.pretty'.dump
dump = function (t) return d (t) end

local mintpal_cookies = require 'tests.api_testkeys'.mintpal

local session = require 'exchange.mintpal' (mintpal_cookies)
assert (session)

local create_retry = require 'tools.util'.create_retry
local retry = create_retry
{
  "timeout",
  "response not from MintPal!", 
  attempts = 20
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
    local r = retry (session.buy, session, "BTC", "LTC", 0.00015, 1.001)

    dump (r)
  end,

  test_sell = function ()
    local r = retry (session.sell, session, "BTC", "AC", 0.015, 1)

    dump (r)
  end,

  test_cancelorder = function ()
    local orders = retry (session.openorders, session, "BTC", "LTC")
    for _, each in ipairs (orders.data) do
      dump (session:cancelorder("BTC", "LTC", each.order_id))
    end
    
    orders = retry (session.openorders, session, "BTC", "AC")
    for _, each in ipairs (orders.data) do
      dump (session:cancelorder("BTC", "AC", each.order_id))
    end
  end,

  test_markethistory = function ()
    local r = retry (session.markethistory, session, "BTC", "LTC")

    assert (next(r))
  end,

  test_orderbook = function ()
    local r = retry (session.orderbook, session, "BTC", "LTC")

    dump (r)
    assert (next(r))
  end,
  
  test_openorders = function ()
    retry (function()
      dump (session:openorders("BTC", "LTC"))
      dump (session:openorders("BTC", "AC"))
      dump (session:openorders("BTC", "BC"))
    end)
  end,

  test_mixcasequery = function ()
    local r = retry (session.orderbook, session, "BtC", "caiX")

    dump (r)
    assert (next(r))
  end
}

utest.run (tests)
-- utest.run_single (tests, "test_orderbook")
