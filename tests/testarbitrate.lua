require 'luarocks_path'
require 'pl.app'.require_here ".."
local arbitrate = require 'arbitrate'
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

local tests = 
{
  test_arbitrate = function ()
    local r = arbitrate (orderbook1, orderbook2)
    assert (r)
    assert (r[1].order_type == "sell")
    assert (r[1].rate == 0.02020000)
    assert (r[2].order_type == "buy")
    assert (r[2].rate == 0.02014990)
    assert (r.amount == 26.00904372)
  end,

  test_reverse_arbitrate = function ()
    local r = arbitrate (orderbook2, orderbook1)
    assert (r)
    assert (r[2].order_type == "sell")
    assert (r[2].rate == 0.02020000)
    assert (r[1].order_type == "buy")
    assert (r[1].rate == 0.02014990)
    assert (r.amount == 26.00904372)
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
    assert (r.amount == 1.73)
    assert (r[1].order_type == "sell")
    assert (r[1].rate == 7.11)
    assert (r[2].order_type == "buy")
    assert (r[2].rate == 3)
  end
}

utest.run (tests)
