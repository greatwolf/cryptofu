local https          = require 'ssl.https'
local crypto         = require 'crypto'
local json           = require 'dkjson'
local tablex         = require 'pl.tablex'
local urlencode_parm = require 'tools.util'.urlencode_parm
local z              = require 'zlib' -- for gzip

local url = "https://poloniex.com"

local pol_query = function (method, urlpath, headers, data)
  local req_headers = { connection = "keep-alive", ["accept-encoding"] = "gzip", }
  if headers then tablex.update (req_headers, headers) end
  local resp, _, errmsg = {}
  local r, c, h, s = https.request
    {
      method = method,
      url = url .. urlpath,
      headers = req_headers,
      source = data and ltn12.source.string (data),
      sink = ltn12.sink.table (resp),
    }
  resp = table.concat (resp)
  if not r then print ("query err:", r, c, h, s); os.exit (1) end
  assert (r, c)

  if h["content-encoding"] == "gzip" then
    resp = z.inflate (resp):read "*a"
  end
  resp, _, errmsg = json.decode (resp)
  return resp or { error = errmsg }
end

local pol_privquery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd
  parm.nonce = self.nonce
  parm.currencyPair = parm.currencyPair and parm.currencyPair:upper()

  local post_data = urlencode_parm (parm)
  self.headers["content-length"] = #post_data
  self.headers.sign = crypto.hmac.digest ("sha512", post_data, self.secret)
  self.nonce = self.nonce + 1

  return pol_query ("POST", "/tradingApi", self.headers, post_data)
end

local pol_pubquery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd
  parm.currencyPair = parm.currencyPair and parm.currencyPair:upper()

  return pol_query ("GET", "/public?" .. urlencode_parm (parm))
end

local poloniex_api = {}
function poloniex_api:balance ()
  local r = pol_privquery (self, "returnBalances")
  if r.error then return nil, r.error end

  local balances = r
  for code, balance in pairs (balances) do
    balances[code] = tonumber (balance)
    if balances[code] == 0 then
      balances[code] = nil
    end
  end
  balances.BTC = balances.BTC or 0
  return balances
end

function poloniex_api:tradehistory (market1, market2)
  local r = pol_privquery (self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
  if r.error then return nil, r.error end
  return r
end

function poloniex_api:buy (market1, market2, rate, quantity)
  local r = pol_privquery (self, "buy", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
  if r.error then return nil, r.error end
  return r
end

function poloniex_api:sell (market1, market2, rate, quantity)
  local r = pol_privquery (self, "sell", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
  if r.error then return nil, r.error end
  return r
end

function poloniex_api:cancelorder (market1, market2, ordernumber)
  local r = pol_privquery (self, "cancelOrder", {currencyPair = market1 .. "_" .. market2, orderNumber = ordernumber})
  if r.error then return nil, r.error end
  return r
end

function poloniex_api:markethistory (market1, market2)
  local r = pol_pubquery (self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
  if r.error then return nil, r.error end
  return r
end

function poloniex_api:orderbook (market1, market2)
  local r = pol_pubquery (self, "returnOrderBook", {currencyPair = market1 .. "_" .. market2})
  if r.error then return nil, r.error end

  r.buy  = tablex.zip (unpack (r.bids))
  r.sell = tablex.zip (unpack (r.asks))
  -- price table at index 1 and amount table at index 2
  -- connect them to the right field name and remove old reference
  r.buy.price,   r.buy[1] = r.buy[1], nil
  r.buy.amount,  r.buy[2] = r.buy[2], nil
  r.sell.price,  r.sell[1] = r.sell[1], nil
  r.sell.amount, r.sell[2] = r.sell[2], nil
  r.bids, r.asks = nil
  return r
end

function poloniex_api:openorders (market1, market2)
  local r = pol_privquery (self, "returnOpenOrders", {currencyPair = market1 .. "_" .. market2})
  if r.error then return nil, r.error end
  return r
end

local session_mt = { __index = poloniex_api }
function poloniex_api:__call (t)
  assert (t and t.key and t.secret, "No api key/secret parameter given.")

  local headers =
  {
    key = t.key, ["content-type"] = "application/x-www-form-urlencoded",
  }
  return setmetatable({ headers = headers, secret = t.secret, nonce = os.time() * 2 }, session_mt)
end

return setmetatable(poloniex_api, poloniex_api)
