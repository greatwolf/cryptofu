local tablex = require 'pl.tablex'

local isempty = function (t)
  return not next (t)
end

local compute_arb = function (orderbook1, orderbook2)
--[[ arbitration algorithm
orderbook 1               orderbook 2
buy                       sell
                            0.02018989	0.00015972	
                            0.02016002	1.47555059	
                            0.02016001	6.35601551	
                            0.02015999	3.94617200	
                            0.02014996	8.32493600	
                            0.02014992	66.04248947	
                            0.02014990	39.63971162	->> 39.02813755 ->> 21.45727557 ->> 13.62995628

0.02040001	0.61086245	x
0.02040000	17.57086198	x
0.02020000	7.82731929	x
0.02010000	57.32231791	
0.01985023	3.07442252	


while sell_pos.price < buy_pos.price
  last_sellprice = sell_pos.price
  last_buyprice = buy_pos.price
  if sell_pos.amount < buy_pos.amount
    accum += sell_pos.amount
    buy_pos.amount -= sell_pos.amount
    sell_pos++
  else 
    accum += buy_pos.amount
    sell_pos.amount -= buy_pos.amount
    buy_pos++
  
buy/sell amount
+0.61086245
+17.57086198
+7.82731929

final output:
  buy 26.00904372 @0.02014990
  sell 26.00904372 @0.02020000
--]]
  local ask_amounts = tablex.icopy ({}, orderbook2.asks.amount)
  local bid_amounts = tablex.icopy ({}, orderbook1.bids.amount)

  local sells, buys = orderbook2.asks.price, orderbook1.bids.price
  local ask_index, bid_index = 1, 1
  local r = { buy  = orderbook2, sell = orderbook1, }
  while sells[ask_index] and 
        buys[bid_index] and 
        sells[ask_index] < buys[bid_index] do
    table.insert (r, { buyprice = sells[ask_index], sellprice = buys[bid_index] })
    r[#r].amount = math.min (ask_amounts[ask_index], bid_amounts[bid_index])
    ask_amounts[ask_index] = ask_amounts[ask_index] - r[#r].amount
    bid_amounts[bid_index] = bid_amounts[bid_index] - r[#r].amount
    if bid_amounts[bid_index] == 0 then bid_index = bid_index + 1 end
    if ask_amounts[ask_index] == 0 then ask_index = ask_index + 1 end
  end
  return #r > 0 and r
end

local arbitrate = function (orderbook1, orderbook2)
  if not isempty (orderbook1.bids.price) and
     not isempty (orderbook2.asks.price) and
     orderbook2.asks.price[1] < orderbook1.bids.price[1] then
    return compute_arb (orderbook1, orderbook2)
  end

  if not isempty (orderbook2.bids.price) and
     not isempty (orderbook1.asks.price) and
     orderbook1.asks.price[1] < orderbook2.bids.price[1] then
    return compute_arb (orderbook2, orderbook1)
  end
  return false
end

local makearb = function (apiname1, apiname2, market1, market2, arbhandler_callback)
  local log = require 'tools.logger' (apiname1 .. "<->" .. apiname2 .. " " .. market1 .. "/" .. market2)
  local api1 = require ("exchange." .. apiname1)
  local api2 = require ("exchange." .. apiname2)
  local main = function ()
    local o1, o2
    while true do
      local noerr, errmsg = pcall (function ()
          o1 = api1:orderbook (market1, market2)
          o2 = api2:orderbook (market1, market2)

        local res = arbitrate (o1, o2)
        if res then
          res.buy  = res.buy == o1 and apiname1 or apiname2
          res.sell = res.sell == o2 and apiname2 or apiname1
          arbhandler_callback { res, [apiname1] = api1, [apiname2] = api2, log = log}
        end
      end)
      log._if (not noerr, errmsg)
      if not noerr and errmsg:match "wantread" then break end
      coroutine.yield ()
    end
  end

  return { main = main, interval = 4 }
end

return { arbitrate = arbitrate, makearb = makearb }
