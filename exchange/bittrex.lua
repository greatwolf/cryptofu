local crypto = require 'crypto'
local tablex = require 'pl.tablex'
local urlencode_parm = require 'tools.util'.urlencode_parm
local map_transpose  = require 'tools.util'.map_transpose
local nonce          = require 'tools.util'.nonce
local apiquery       = require 'tools.apiquery'
local dump = require 'pl.pretty'.dump


local url = "https://bittrex.com"
local apiv = "/api/v1.1"

local bittrex_privquery = function (self, cmd, parm)
  parm = parm or {}
  parm.apikey = self.key
  parm.nonce = nonce ()
  parm.market = parm.market and parm.market:upper()

  local urlpath = cmd .. "?" .. urlencode_parm (parm)
  local uri = url .. apiv .. urlpath
  local headers = { apisign = crypto.hmac.digest ("sha512", uri, self.secret) }

  return apiquery.getrequest (url, apiv .. urlpath, headers)
end

local bittrex_pubquery = function (self, cmd, parm)
  parm = parm or {}
  parm.market = parm.market and parm.market:upper()

  return apiquery.getrequest (url .. apiv, string.format ("%s?%s", 
                                                          cmd, urlencode_parm (parm)))
end

local bittrex_api = {}
function bittrex_api:balance ()
  local r = bittrex_privquery (self, "/account/getbalances")
  if not r.success then return nil, r.message end

  local portfolio = r.result
  for i, coin in ipairs (portfolio) do
    local avail = tonumber (coin.Available)
    portfolio[coin.Currency] = avail > 0 and avail or nil
    portfolio[i] = nil
  end
  portfolio.BTC = portfolio.BTC or 0
  return portfolio
end

function bittrex_api:tradehistory (market1, market2)
  local r = bittrex_privquery (self, "/account/getorderhistory", {market = market1 .. "-" .. market2})
  if not r.success then return nil, r.message end
  return r.result
end

function bittrex_api:buy (market1, market2, rate, quantity)
  local r = bittrex_privquery (self, "/market/buylimit", {market = market1 .. "-" .. market2, rate = rate, quantity = quantity})
  if not r.success then return nil, r.message end
  r.result.uuid, r.result.orderNumber = nil, r.result.uuid
  return r.result
end

function bittrex_api:sell (market1, market2, rate, quantity)
  local r = bittrex_privquery (self, "/market/selllimit", {market = market1 .. "-" .. market2, rate = rate, quantity = quantity})
  if not r.success then return nil, r.message end
  r.result.uuid, r.result.orderNumber = nil, r.result.uuid
  return r.result
end

function bittrex_api:cancelorder (market1, market2, ordernumber)
  local r = bittrex_privquery (self, "/market/cancel", {market = market1 .. "-" .. market2, uuid = ordernumber})
  if not r.success then return nil, r.message end
  return r
end

function bittrex_api:markethistory (market1, market2)
  local r = bittrex_pubquery (self, "/public/getmarkethistory", {market = market1 .. "-" .. market2})
  if not r.success then return nil, r.message end
  return r.result
end

function bittrex_api:orderbook (market1, market2)
  local r = bittrex_pubquery (self, "/public/getorderbook",
                              {market = market1 .. "-" .. market2,
                              ["type"] = "both"})
  if not r.success then return nil, r.message end
  r = r.result

  r.bids = map_transpose (r.buy, { Rate = "price", Quantity = "amount" })
  r.asks = map_transpose (r.sell, { Rate = "price", Quantity = "amount" })
  r.buy, r.sell = nil

  return r
end

function bittrex_api:openorders (market1, market2)
  local r = bittrex_privquery (self, "/market/getopenorders", {market = market1 .. "-" .. market2})
  if not r.success then return nil, r.message end
  return r.result
end

local session_mt = { __index = bittrex_api }
function bittrex_api.tradingapi (key, secret)
  assert (key and secret, "No api key/secret parameter given.")

  return setmetatable({ key = key, secret = secret }, session_mt)
end

return setmetatable(bittrex_api, bittrex_api)
