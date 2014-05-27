local https = require 'ssl.https'
local crypto = require 'crypto'
local json = require 'dkjson'
local util = require 'util'

local urlencode_parm, create_retry, log = util.urlencode_parm, util.create_retry, util.log
local url = "https://poloniex.com"

local privatequery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd
  parm.nonce = os.time() * 2

  local post_data = urlencode_parm (parm)
  self.headers.connection = "keep-alive"
  self.headers["content-length"] = #post_data
  self.headers.sign = crypto.hmac.digest ("sha512", post_data, self.secret)

  local resp = {}
  local elapse = os.clock()
  local r, c, h = https.request
    {
      method = "POST",
      url = url .. "/tradingApi",
      headers = self.headers,
      source = ltn12.source.string (post_data),
      sink = ltn12.sink.table (resp),
    }
  print ((os.clock() - elapse) .. "s")
  assert (r, c)
  return json.decode( table.concat(resp) )
end

local publicquery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd

  local resp = {}
  local elapse = os.clock()
  local r, c, h = https.request
    {
      url = url .. "/public?" .. urlencode_parm (parm),
      headers = { connection = "keep-alive" },
      sink = ltn12.sink.table (resp),
    }
  print ((os.clock() - elapse) .. "s")
  assert (r, c)
  return json.decode( table.concat(resp) )
end

local retry = create_retry
{
  "timeout",
  attempts = 3
}

local poloniex_api = {}
function poloniex_api:balance ()
  local balances = retry (privatequery, self, "returnBalances")
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
  return retry (privatequery, self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:buy (market1, market2, rate, quantity)
  return retry (privatequery, self, "buy", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
end

function poloniex_api:sell (market1, market2, rate, quantity)
  return retry (privatequery, self, "sell", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
end

function poloniex_api:cancelorder (market1, market2, ordernumber)
  return retry (privatequery, self, "cancelOrder", {currencyPair = market1 .. "_" .. market2, orderNumber = ordernumber})
end

function poloniex_api:markethistory (market1, market2)
  return retry (publicquery, self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:orderbook (market1, market2)
  return retry (publicquery, self, "returnOrderBook", {currencyPair = market1 .. "_" .. market2})
end

function poloniex_api:openorders (market1, market2)
  return retry (privatequery, self, "returnOpenOrders", {currencyPair = market1 .. "_" .. market2})
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
