local http, https =     require 'socket.http', require 'ssl.https'
local crypto =          require 'crypto'
local json =            require 'dkjson'
local imap =            require 'pl.tablex'.imap
local update =          require 'pl.tablex'.update
local map_transpose =   require 'tools.util'.map_transpose
local urlencode_parm =  require 'tools.util'.urlencode_parm


-- main helpers
local craptsy_query = function (proto, method, urlpath, headers, data)
  local req_headers = { connection = "keep-alive" }
  if headers then update (req_headers, headers) end
  local resp, _, errmsg = {}
  local r, c, h, s = proto.request
    {
      method = method,
      url = urlpath,
      headers = req_headers,
      source = data and ltn12.source.string (data),
      sink = ltn12.sink.table (resp),
    }
  resp = table.concat (resp)
  if not r then print ("query err:", r, c, h, s); print (debug.traceback()); os.exit (1) end
  assert (r, c)

  resp, _, errmsg = json.decode (resp)
  return resp or { error = errmsg }
end

local craptsy_privquery = function (self, cmd, parm)
  parm = parm or {}
  parm.method = cmd
  parm.nonce = os.time() * 2

  local post_data = urlencode_parm (parm)
  self.headers["content-length"] = #post_data
  self.headers.sign = crypto.hmac.digest ("sha512", post_data, self.secret)

  return craptsy_query (https, "POST", "https://api.cryptsy.com/api", self.headers, post_data)
end

local craptsy_pubquery = function (self, cmd, parm)
  parm = parm or {}
  parm.method = cmd

  return craptsy_query (http, "GET", "http://pubapi.cryptsy.com/api.php?" .. urlencode_parm (parm))
end

local craptsy_getmarketid, craptsy_loadmarketids
do
  local market_ids = {}
  craptsy_getmarketid = function (market1, market2)
    local pair = (market2 .. "/" .. market1):upper()
    return assert (market_ids[pair], "no market pair " .. pair)
  end

  craptsy_loadmarketids = function (self)
    if not next (market_ids) then
      local markets = assert (craptsy_privquery (self, "getmarkets"))
      markets = assert (markets.success == "1" and markets["return"])
      for _, market in pairs(markets) do
        local pair = market.label
        market_ids[pair] = market.marketid
      end
    end
  end
end

local craptsy_api = {}
function craptsy_api:balance ()
  local r = craptsy_privquery (self, "getinfo")
  if r.error then return nil, r.error end

  local balances = r["return"].balances_available
  for code, balance in pairs (balances) do
    balances[code] = tonumber (balance)
    if balances[code] == 0 then
      balances[code] = nil
    end
  end
  balances.BTC = balances.BTC or 0
  return balances
end

function craptsy_api:tradehistory (market1, market2)
  local r = craptsy_privquery (self, "mytrades", {marketid = craptsy_getmarketid (market1, market2)})
  if r.error then return nil, r.error end
  return r["return"]
end

function craptsy_api:buy (market1, market2, rate, quantity)
  local r = craptsy_privquery (self, "createorder", {marketid = craptsy_getmarketid (market1, market2), 
                                                     ordertype = "Buy", quantity = quantity, price = rate})
  if r.error then return nil, r.error end
  r.orderNumber, r.orderid, r.success = tonumber (r.orderid)
  return r
end

function craptsy_api:sell (market1, market2, rate, quantity)
  local r = craptsy_privquery (self, "createorder", {marketid = craptsy_getmarketid (market1, market2), 
                                                     ordertype = "Sell", quantity = quantity, price = rate})
  if r.error then return nil, r.error end
  r.orderNumber, r.orderid, r.success = tonumber (r.orderid)
  return r
end

function craptsy_api:cancelorder (market1, market2, ordernumber)
  local r = craptsy_privquery (self, "cancelorder", {orderid = ordernumber})
  if r.error then return nil, r.error end
  return r["return"]
end

function craptsy_api:markethistory (market1, market2)
  local r = craptsy_pubquery (self, "singlemarketdata", {marketid = craptsy_getmarketid (market1, market2)})
  if r.error then return nil, r.error end
  return r["return"]
end

function craptsy_api:orderbook (market1, market2)
  local r = craptsy_pubquery (self, "singleorderdata", {marketid = craptsy_getmarketid (market1, market2)})
  if r.error then return nil, r.error end

  local orderbook = r["return"][market2:upper()]
  orderbook.buy  = map_transpose (orderbook.buyorders, { quantity = "amount" })
  orderbook.sell = map_transpose (orderbook.sellorders, { quantity = "amount" })
  orderbook.buy.price   = imap (tonumber, orderbook.buy.price)
  orderbook.buy.amount  = imap (tonumber, orderbook.buy.amount)
  orderbook.sell.price  = imap (tonumber, orderbook.sell.price)
  orderbook.sell.amount = imap (tonumber, orderbook.sell.amount)
  -- remove the fields we don't care about
  orderbook.buy.total, orderbook.sell.total, orderbook.buyorders, orderbook.sellorders = nil
  orderbook.label, orderbook.marketid = nil
  orderbook.primarycode, orderbook.primaryname = nil
  orderbook.secondarycode, orderbook.secondaryname = nil
  return orderbook
end

function craptsy_api:openorders (market1, market2)
  local r = craptsy_privquery (self, "myorders", {marketid = craptsy_getmarketid (market1, market2)})
  if r.error then return nil, r.error end
  return r["return"]
end

local session_mt = { __index = craptsy_api }
function craptsy_api:__call (t)
  assert (t and t.key and t.secret, "No api key/secret parameter given.")

  local headers =
  {
    key = t.key,
  }
  local session = setmetatable({ headers = headers, secret = t.secret }, session_mt)
  craptsy_loadmarketids (session)
  return session
end

return setmetatable(craptsy_api, craptsy_api)
