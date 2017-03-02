local crypto         = require 'crypto'
local tablex         = require 'pl.tablex'
local apiquery       = require 'tools.apiquery'
local urlencode_parm = require 'tools.util'.urlencode_parm
local nonce          = require 'tools.util'.nonce


local url = "https://poloniex.com"

local function poloniex_authquery (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd
  parm.nonce = nonce ()
  parm.currencyPair = parm.currencyPair and parm.currencyPair:upper()

  local post_data = urlencode_parm (parm)
  self.headers["content-length"] = #post_data
  self.headers.sign = crypto.hmac.digest ("sha512", post_data, self.secret)

  local res = apiquery.postrequest (url, "/tradingApi", self.headers, post_data)
  if res.error then
    -- if it's just a bad nonce, update nonce and retry
    local new_nonce = res.error:match "Nonce must be greater than (%d+)%."
    if new_nonce then
      nonce (new_nonce + 0)
      return poloniex_authquery (self, cmd, parm)
    end
  end
  return res
end

local poloniex_publicquery = function (self, cmd, parm)
  parm = parm or {}
  parm.command = cmd
  parm.currencyPair = parm.currencyPair and parm.currencyPair:upper()

  return apiquery.getrequest (url, "/public?" .. urlencode_parm (parm))
end

local poloniex_publicapi = {}
function poloniex_publicapi:markethistory (market1, market2)
  local r = poloniex_publicquery (self, "returnTradeHistory", {currencyPair = market1 .. "_" .. market2})
  if r.error then return nil, r.error end
  return r
end

function poloniex_publicapi:orderbook (market1, market2)
  local r = poloniex_publicquery (self, "returnOrderBook", {currencyPair = market1 .. "_" .. market2})
  if r.error then return nil, r.error end

  local unpack = unpack or table.unpack
  r.bids  = tablex.zip (unpack (r.bids))
  r.asks = tablex.zip (unpack (r.asks))
  -- price table at index 1 and amount table at index 2
  -- connect them to the right field name and remove old reference
  r.bids.price,  r.bids[1] = r.bids[1], nil
  r.bids.amount, r.bids[2] = r.bids[2], nil
  r.asks.price,  r.asks[1] = r.asks[1], nil
  r.asks.amount, r.asks[2] = r.asks[2], nil
  tablex.transform(tonumber, r.bids.price)
  tablex.transform(tonumber, r.asks.price)

  return r
end

function poloniex_publicapi:lendingbook (currency)
  local r = poloniex_publicquery (self, "returnLoanOrders", {currency = currency})
  if r.error then return nil, r.error end
  return r
end

local poloniex_lendingapi = {}
function poloniex_lendingapi:placeoffer (currency, rate, quantity, duration, autorenew)
  local parm =
    {
      currency = currency,
      lendingRate = rate,
      amount = quantity,
      duration = duration or 2,
      autoRenew = autorenew and 1 or 0
    }
  local r = self.authquery ("createLoanOffer", parm)
  if r.error then return nil, r.error end
  return r
end

function poloniex_lendingapi:canceloffer (orderid)
  local r = self.authquery ("cancelLoanOffer", {orderNumber = orderid})
  if r.error then return nil, r.error end
  return r
end

function poloniex_lendingapi:openoffers (currency)
  local r = self.authquery ("returnOpenLoanOffers")
  if r.error then return nil, r.error end
  if not currency then return r end
  return r[currency] or {}
end

function poloniex_lendingapi:activeoffers (currency)
  local r = self.authquery ("returnActiveLoans")
  if r.error then return nil, r.error end
  r = r.provided
  if not currency then return r end
  return tablex.filter (r, function (v) return v.currency == currency end)
end

function poloniex_lendingapi:balance ()
  local r = self.authquery ("returnAvailableAccountBalances", {account = "lending"})
  if r.error then return nil, r.error end
  return r.lending
end

local poloniex_tradingapi = {}
function poloniex_tradingapi:balance ()
  local r = self.authquery ("returnAvailableAccountBalances", {account = "exchange"})
  if r.error then return nil, r.error end
  return r.exchange
end

function poloniex_tradingapi:tradehistory (market1, market2, start_period, stop_period)
  local parm =
    {
      currencyPair = market1 .. "_" .. market2,
      start = start_period or 1,
      ['end'] = stop_period
    }
  local r = self.authquery ("returnTradeHistory", parm)
  if r.error then return nil, r.error end
  return r
end

function poloniex_tradingapi:buy (market1, market2, rate, quantity)
  local r = self.authquery ("buy", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
  if r.error then return nil, r.error end
  return r
end

function poloniex_tradingapi:sell (market1, market2, rate, quantity)
  local r = self.authquery ("sell", {currencyPair = market1 .. "_" .. market2, rate = rate, amount = quantity})
  if r.error then return nil, r.error end
  return r
end

function poloniex_tradingapi:cancelorder (ordernumber)
  local r = self.authquery ("cancelOrder", {orderNumber = ordernumber})
  if r.error then return nil, r.error end
  return r
end

function poloniex_tradingapi:moveorder (ordernumber, newrate, quantity)
  local parm =
    {
      orderNumber = ordernumber,
      rate = newrate,
      amount = quantity
    }
  local r = self.authquery ("moveOrder", parm)
  if r.error then return nil, r.error end
  return r
end

function poloniex_tradingapi:openorders (market1, market2)
  local r = self.authquery ("returnOpenOrders", {currencyPair = market1 .. "_" .. market2})
  if r.error then return nil, r.error end
  return r
end

local make_authself = function (apikey, apisecret)
  return
  {
    headers =
    {
      key = apikey, ["content-type"] = "application/x-www-form-urlencoded",
    },
    secret = apisecret,
  }
end

local make_apifactory = function (apimethods)
  return function (apikey, apisecret)
    assert (apikey and apisecret, "No api key/secret parameter given.")

    local self        = make_authself (apikey, apisecret)
    local new_api     = tablex.update ({}, apimethods)
    new_api.authquery = function (...)
                          return poloniex_authquery (self, ...)
                        end
    return new_api
  end
end

poloniex_publicapi.lendingapi = make_apifactory (poloniex_lendingapi)
poloniex_publicapi.tradingapi = make_apifactory (poloniex_tradingapi)

return poloniex_publicapi
