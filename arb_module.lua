local pl
local create_retry
local trex, pol, apikeys

local arb


local dump_orderbook = function (o, name, depth)
  local min = math.min
  io.write (string.format ("[%s - %s]\n", name, tostring(o)))
  io.write (string.format ("%12s %12s %14s %13s\n",
                           "sell price", "sell amount",
                           "buy price", "buy amount"))
  depth = depth or 200
  depth = min (depth, min (#o.sell.price, #o.buy.price))

  for i = 1, depth do
    local out = string.format ("%12.8f %12.4f || %12.8f %12.4f",
                               o.sell.price[i], o.sell.amount[i],
                               o.buy.price[i], o.buy.amount[i])
    print (out)
  end
end

local arb_module = {}

arb_module.startup = function ()
  pl = require 'pl.import_into' ()
  apikeys = require 'apikeys'
  make_retry = require 'tools.retry'
  trex = require 'exchange.bittrex' (apikeys.bittrex)
  pol = require 'exchange.poloniex' (apikeys.poloniex)
  trex = make_retry (trex, 4, "timeout", "closed")
  pol = make_retry (pol, 4, "timeout", "closed")

  arb = require 'arbitrate'.arbitrate
  log = require 'tools.logger' "Arb"
end

arb_module.main = function ()
  local dump = require 'pl.pretty'.dump
  local timer = require 'pl.test'.timer

  local trex_orders, pol_orders
  local arb_str = "%s buy %.8f => %s sell %.8f, Qty: %.8f"
  while true do
    local noerr, errmsg = pcall (function ()
      timer ("pol orderbook", 1, function ()
        pol_orders = pol:orderbook ("BTC", "XMR")
      end)
      timer ("trex orderbook", 1, function ()
        trex_orders = trex:orderbook ("BTC", "XMR")
      end)

      local res = arb (trex_orders, pol_orders)
      if res then
        res.buy  = res.buy == trex_orders and "bittrex" or "poloniex"
        res.sell = res.sell == pol_orders and "poloniex" or "bittrex"
        for _, v in ipairs (res) do
          local prof_spread = v.amount * (v.sellprice - v.buyprice)
          log (arb_str:format (res.buy, v.buyprice,
                               res.sell, v.sellprice,
                               v.amount, prof_spread))
          log ( ("Risking: %.8f -> Profit: %.8f btc, ratio: %.6f"):format (v.buyprice * v.amount, 
                                                                           prof_spread, 
                                                                           100*prof_spread / (v.buyprice * v.amount) ))
        end
        -- local o1, o2
        -- timer ("trex buy", 1, function () o1 = trex:buy ("BTC", "CINNI", 0.000011, 10.001) end)
        -- timer ("pol buy", 1, function () o2 = pol:buy ("BTC", "CINNI", 0.000011, 10.001) end)
        -- dump (o1); dump (o2)
        -- timer ("trex cancel", 1, function ()
          -- if o1.orderNumber then
            -- o1 = trex:cancelorder ("BTC", "CINNI", o1.orderNumber)
          -- else
            -- local o1 = assert (trex:openorders ("BTC", "CINNI"))
            -- for each, order in ipairs (o1) do
              -- assert (trex:cancelorder ("BTC", "CINNI", order.order_id))
            -- end
          -- end
        -- end)
        -- timer ("pol cancel", 1, function () 
          -- o2 = pol:cancelorder ("BTC", "CINNI", o2.orderNumber)
        -- end)
        -- dump (o1); dump (o2)
        -- assert (o1 and o1.response == "success")
        -- assert (o2 and o2.success == 1)

        dump_orderbook (trex_orders, "bittrex", 4)
        dump_orderbook (pol_orders, "poloniex", 4)
      end
    end)
    log._if (not noerr, errmsg)
    if not noerr and errmsg:match "wantread" then break end
    coroutine.yield ()
  end
end

arb_module.interval = 4 -- secs

return arb_module
