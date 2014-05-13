local https = require 'ssl.https'
local crypto = require 'crypto'
local json = require 'dkjson'

local url = "https://poloniex.com"

local urlencode_parm = function (t)
  assert (type(t) == "table")
  local parm = {}
  for k, v in pairs(t) do
    table.insert (parm, k .. "=" .. v)
  end
  return table.concat (parm, "&")
end

local privatequery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd
  parm.nonce = os.time() * 2
  local post_data = urlencode_parm (parm)
  self.headers["content-length"] = #post_data
  self.headers.Sign = crypto.hmac.digest ("sha512", post_data, self.secret)

  local resp = {}
  local r, c = https.request
  {
    method = "POST",
    url = url .. "/tradingApi",
    headers = self.headers,
    source = ltn12.source.string (post_data),
    sink = ltn12.sink.table (resp),
  }
  if not r then return nil, c end
  return json.decode( table.concat(resp) )
end

local publicquery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd

  local resp = {}
  local r, c = https.request
  {
    url = url .. "/public?" .. urlencode_parm (parm),
    sink = ltn12.sink.table (resp),
  }
  if not r then return nil, c end
  return json.decode( table.concat(resp) )
end

local poloniex_api = {}
function poloniex_api:balance ()
  return privatequery (self, "returnBalances")
end

function poloniex_api:tradehistory (market1, market2)
  return privatequery (self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:buy (market1, market2, rate, quantity)
  return privatequery (self, "buy", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
end

function poloniex_api:sell (market1, market2, rate, quantity)
  return privatequery (self, "sell", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
end

function poloniex_api:cancelorder (market1, market2, ordernumber)
  return privatequery (self, "cancelOrder", {currencyPair = market1 .. "_" .. market2, orderNumber = ordernumber})
end

function poloniex_api:markethistory (market1, market2)
  return publicquery (self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:orderbook (market1, market2)
  return publicquery (self, "returnOrderBook", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:openorders (market1, market2)
  return publicquery (self, "returnOpenOrders", {currencyPair = market1 .. "_" .. market2})
end

local session_mt = { __index = poloniex_api }
function poloniex_api:__call (t)
  assert (t and t.key and t.secret, "No api key/secret parameter given.")

  local headers =
  {
    Key = t.key, ["content-type"] = "application/x-www-form-urlencoded",
  }
  return setmetatable({ headers = headers, secret = t.secret }, session_mt)
end

return setmetatable(poloniex_api, poloniex_api)
