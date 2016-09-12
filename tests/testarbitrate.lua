require 'pl.app'.require_here ".."
local arb_tool = require 'arbitrate'
local arbitrate = arb_tool.arbitrate
local makearb = arb_tool.makearb
local utest = require 'unittest'

local orderbook1 =
{
  buy =
  {
    price = 
    {
      0.02040001,
      0.02040000,
      0.02020000,
      0.02010000,
      0.01985023,
    },
    amount = 
    {
      0.61086245,
      17.57086198,
      7.82731929,
      57.32231791,
      3.07442252,
    }
  },
  sell = { price = {0.02050001,}, amount = {0.31086,} }
}
local orderbook2 =
{
  buy = { price = {0.01995,}, amount = {0.016,} },
  sell =
  {
    price = 
    {
      0.02014990,
      0.02014992,
      0.02014996,
      0.02015999,
      0.02016001,
      0.02016002,
      0.02018989,
    },
    amount = 
    {
      39.63971,
      66.04248947,
      8.32493600,
      3.94617200,
      6.35601551,
      1.47555059,
      0.00015972,
    }
  }
}

utest.group "tests_arb"
{
  test_arbitrate = function ()
    local r = arbitrate (orderbook1, orderbook2)
    assert (r)
    assert (r.buy  == orderbook2)
    assert (r.sell == orderbook1)
    assert (r[1].buyprice  == orderbook2.sell.price[1])
    assert (r[1].sellprice == orderbook1.buy.price[1])
    assert (r[1].amount == orderbook1.buy.amount[1])
    assert (r[2].buyprice  == orderbook2.sell.price[1])
    assert (r[2].sellprice == orderbook1.buy.price[2])
    assert (r[2].amount == orderbook1.buy.amount[2])
    assert (r[3].buyprice  == orderbook2.sell.price[1])
    assert (r[3].sellprice == orderbook1.buy.price[3])
    assert (r[3].amount == orderbook1.buy.amount[3])
  end,

  test_reverse_arbitrate = function ()
    local r = arbitrate (orderbook2, orderbook1)
    assert (r)
    assert (r.buy  == orderbook2)
    assert (r.sell == orderbook1)
    assert (r[1].buyprice  == orderbook2.sell.price[1])
    assert (r[1].sellprice == orderbook1.buy.price[1])
    assert (r[1].amount == orderbook1.buy.amount[1])
    assert (r[2].buyprice  == orderbook2.sell.price[1])
    assert (r[2].sellprice == orderbook1.buy.price[2])
    assert (r[2].amount == orderbook1.buy.amount[2])
    assert (r[3].buyprice  == orderbook2.sell.price[1])
    assert (r[3].sellprice == orderbook1.buy.price[3])
    assert (r[3].amount == orderbook1.buy.amount[3])
  end,

  test_emptybook_arbitrate = function ()
    local r = arbitrate ({buy = {price ={}, amount = {}}, sell = {price ={}, amount = {}}},
                         {buy = {price ={}, amount = {}}, sell = {price ={}, amount = {}}})
    assert (not r)
  end,

  test_no_arbitrate = function ()
    local orderbook1 =
    {
      buy =
      {
        price = 
        {
          0.02010000,
          0.01985023,
        },
        amount = 
        {
          57.32231791,
          3.07442252,
        }
      },
      sell = { price = {0.02050001,}, amount = {0.31086,} }
    }
    local orderbook2 =
    {
      buy = { price = {0.01995,}, amount = {0.016,} },
      sell =
      {
        price = 
        {
          0.02016002,
          0.02018989,
        },
        amount = 
        {
          1.47555059,
          0.00015972,
        }
      }
    }
    local r = arbitrate (orderbook1, orderbook2)
    assert (not r)
  end,

  test_equalqty_arbitrate = function ()
    local orderbook1 = 
    {
      buy =
      {
        price =
        {
          9,
          8,
          7,
          6,
          5,
        },
        amount = 
        {
          5,
          5,
          6.5,
          20,
          5,
        }
      },
      sell = { price = {10}, amount = {1} }
    }
    local orderbook2 =
    {
      sell =
      {
        price =
        {
          4,
          5,
          6,
          7,
        },
        amount = 
        {
          10,
          5,
          2,
          3,
        }
      },
      buy = { price = {2}, amount = {1} }
    }
    local r = arbitrate (orderbook1, orderbook2)
    assert (r)
    assert (r.buy == orderbook2 and r.sell == orderbook1)
    assert (r[1].buyprice == orderbook2.sell.price[1] and 
            r[1].sellprice == orderbook1.buy.price[1] and 
            r[1].amount == 5)
    assert (r[2].buyprice == orderbook2.sell.price[1] and 
            r[2].sellprice == orderbook1.buy.price[2] and 
            r[2].amount == 5)
    assert (r[3].buyprice == orderbook2.sell.price[2] and 
            r[3].sellprice == orderbook1.buy.price[3] and 
            r[3].amount == 5)
  end,

  test_thinbuy_arbitrate = function ()
    local orderbook1 =
    {
      buy =
      {
        price  = {   8, 7.11, },
        amount = { 0.5, 1.23, }
      },
      sell = { price = {}, amount = {} }
    }
    local orderbook2 =
    {
      buy = { price = {}, amount = {} },
      sell =
      {
        price  = {    2, 3, 3.6, 4.8, },
        amount = { 0.23, 4, 1.2, 0.6, }
      }
    }
    local r = arbitrate (orderbook1, orderbook2)
    assert (r)
    assert (r.buy == orderbook2 and r.sell == orderbook1)
    assert (r[1].buyprice == 2 and 
            r[1].sellprice == 8 and
            r[1].amount == 0.23)
    assert (r[2].buyprice == 3 and
            r[2].sellprice == 8 and
            r[2].amount == 0.27)
    assert (r[3].buyprice == 3 and
            r[3].sellprice == 7.11 and
            r[3].amount == 1.23)
    assert (not r[4])
  end
}

local makemock = function (orderbook, spy)
  return function ()
    return
    {
      __call = function (self, apikey) return self end,
      orderbook = function (self, market1, market2)
        spy.called_orderbook = true
        return orderbook
      end
    }
  end
end

local arbhandler_spy = {}
local arbhandler = function (ctx)
  arbhandler_spy.called_handler = true
  arbhandler_spy.context = ctx
end

local mock1spy, mock2spy = {}, {}
package.preload["exchange.mock1"] = makemock (orderbook1, mock1spy)
package.preload["exchange.mock2"] = makemock (orderbook2, mock2spy)
local arbmodule = makearb ('mock1', 'mock2', 'btc', 'ltc', arbhandler)
arbmodule.main = coroutine.create (arbmodule.main)
coroutine.resume (arbmodule.main)

utest.group "tests_makearb"
{
  test_orderbookcall = function ()
    assert (mock1spy.called_orderbook)
    assert (mock2spy.called_orderbook)
  end,

  test_callbackparam = function ()
    assert (arbhandler_spy.called_handler)
    assert (arbhandler_spy.context[1]) -- arbitration data
    assert (arbhandler_spy.context.mock1)
    assert (arbhandler_spy.context.mock2)
    assert (arbhandler_spy.context.log)
  end
}

utest.run "tests_arb"
utest.run "tests_makearb"
