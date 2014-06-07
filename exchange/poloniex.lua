local https = require 'ssl.https'
local crypto = require 'crypto'
local json = require 'dkjson'
local tablex = require 'pl.tablex'
local util = require 'tools.util'
local zip = require 'pl.tablex'.zip

local urlencode_parm, log = util.urlencode_parm, util.log
local url = "https://poloniex.com"

local pol_query = function (method, urlpath, headers, data)
  local req_headers = { connection = "keep-alive" }
  if headers then tablex.update (req_headers, headers) end
  local resp = {}
  local r, c, h = https.request
    {
      method = method,
      url = url .. urlpath,
      headers = req_headers,
      source = data and ltn12.source.string (data),
      sink = ltn12.sink.table (resp),
    }
  assert (r, c)

  resp = table.concat(resp)
  assert (#resp > 0, "empty response!")
  resp = json.decode (resp)
  return assert (not resp.error, resp.error) and resp
end

local pol_privquery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd
  parm.nonce = os.time() * 2
  parm.currencyPair = parm.currencyPair and parm.currencyPair:upper()

  local post_data = urlencode_parm (parm)
  self.headers["content-length"] = #post_data
  self.headers.sign = crypto.hmac.digest ("sha512", post_data, self.secret)

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
  local balances = pol_privquery (self, "returnBalances")
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
  return pol_privquery (self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:buy (market1, market2, rate, quantity)
  return pol_privquery (self, "buy", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
end

function poloniex_api:sell (market1, market2, rate, quantity)
  return pol_privquery (self, "sell", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
end

function poloniex_api:cancelorder (market1, market2, ordernumber)
  return pol_privquery (self, "cancelOrder", {currencyPair = market1 .. "_" .. market2, orderNumber = ordernumber})
end

function poloniex_api:markethistory (market1, market2)
  return pol_pubquery (self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:orderbook (market1, market2)
  local r = pol_pubquery (self, "returnOrderBook", {currencyPair = market1 .. "_" .. market2})
  r.buy  = zip (unpack (r.bids))
  r.sell = zip (unpack (r.asks))
  -- price table at index 1 and amount table at index 2
  -- connect them to the right field name and remove old reference
  r.buy.price, r.buy.amount = r.buy[1], r.buy[2]
  r.sell.price, r.sell.amount = r.sell[1], r.sell[2]
  r.buy[1], r.buy[2], r.sell[1], r.sell[2] = nil
  r.bids, r.asks = nil
  return r
end

function poloniex_api:openorders (market1, market2)
  return pol_privquery (self, "returnOpenOrders", {currencyPair = market1 .. "_" .. market2})
end

local session_mt = { __index = poloniex_api }
function poloniex_api:__call (t)
  assert (t and t.key and t.secret, "No api key/secret parameter given.")

  local headers =
  {
    key = t.key, ["content-type"] = "application/x-www-form-urlencoded",
  }
  return setmetatable({ headers = headers, secret = t.secret }, session_mt)
end

return setmetatable(poloniex_api, poloniex_api)
