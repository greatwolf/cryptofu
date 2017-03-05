local apiquery       = require 'tools.apiquery'
local nonce          = require 'tools.util'.nonce
local urlencode_parm = require 'tools.util'.urlencode_parm
local tablex  = require 'pl.tablex'
local hmac    = require 'crypto'.hmac
local json    = require 'dkjson'
local base64  = require 'basexx'.to_base64


local apiv = "/v1"
local url = "https://api.bitfinex.com" .. apiv

local function bitfinex_authquery (self, cmd, parm)
  parm = parm or {}
  parm.request = apiv .. cmd
  parm.nonce   = tostring (nonce ())

  local post_data = base64 (json.encode (parm))
  self.headers['X-BFX-PAYLOAD']   = post_data
  self.headers['X-BFX-SIGNATURE'] = hmac.digest ("sha384", post_data, self.secret)

  local res = apiquery.postrequest (url, cmd, self.headers)
  if res[1] == "error" then
    return nil, table.concat(res, " ")
  end

  return res
end

local bitfinex_publicquery = function (self, cmd, parm)
  parm = parm or {}

  local res = apiquery.getrequest (url, cmd .. urlencode_parm (parm))
  if res[1] == "error" then
    return nil, table.concat(res, " ")
  end
  return res
end

-- The way finex handles market symbols is a bit annoying.
-- Their api doesn't have a canonical format nor
-- is it passed as a key-value param.
-- Their 'symbols' api endpoint returns lowercase but the
-- resty path of client request must be uppercase.
local get_marketsymbol
do
  local symbols
  local initsymbols, mapsymbols
  initsymbols = function (market1, market2)
    -- finex's v2 api doesn't have symbol endpoint
    symbols = apiquery.getrequest "https://api.bitfinex.com/v1/symbols"
    symbols = tablex.makeset (tablex.imap (string.upper, symbols))
    get_marketsymbol = mapsymbols
    return get_marketsymbol (market1, market2)
  end
  mapsymbols = function (market1, market2)
    market1, market2 = market1:upper (), market2:upper ()

    if symbols[market2 .. market1] then return market2 .. market1 end
    return market1 .. market2
  end
  get_marketsymbol = initsymbols
end

local bitfinex_publicapi = {}

function bitfinex_publicapi:orderbook (market1, market2)
  local cmd = "/book/%s"
  local sym = get_marketsymbol (market1, market2)
  return bitfinex_publicquery (self, cmd:format (sym))
end

function bitfinex_publicapi:markethistory (market1, market2)
  local cmd = "/trades/%s"
  local sym = get_marketsymbol (market1, market2)
  return bitfinex_publicquery (self, cmd:format (sym))
end

local bitfinex_tradingapi = {}
function bitfinex_tradingapi:balance ()
  return self.authquery ("/balances")
end

function bitfinex_tradingapi:tradehistory (market1, market2, start_period, stop_period)
  local parm =
    {
      symbol = get_marketsymbol (market1, market2),
      timestamp = start_period or 1,
      ['until'] = stop_period
    }
  local r = self.authquery ("/mytrades", parm)
  return r
end

function bitfinex_tradingapi:buy (market1, market2, rate, quantity)
  local parm =
    {
      symbol = get_marketsymbol (market1, market2),
      amount = tostring (quantity),
      price  = tostring (rate),
      side   = "buy",
      type   = "exchange limit",
      is_postonly = true,
    }
  local r = self.authquery ("/order/new", parm)
  return r
end

function bitfinex_tradingapi:sell (market1, market2, rate, quantity)
  local parm =
    {
      symbol = get_marketsymbol (market1, market2),
      amount = tostring (quantity),
      price  = tostring (rate),
      side   = "sell",
      type   = "exchange limit",
      is_postonly = true,
    }
  local r = self.authquery ("/order/new", parm)
  return r
end

function bitfinex_tradingapi:cancelorder (...)
  local order_ids = tablex.filter ({...}, function (v) return type(v) == 'number' end)
  if #order_ids < 1 then
    return { result = "no valid order_ids given." }
  end
  return self.authquery ("/order/cancel/multi", { order_ids = order_ids })
end

function bitfinex_tradingapi:openorders (market1, market2)
  return self.authquery ("/orders")
end

local make_authself = function (apikey, apisecret)
  return
  {
    headers =
    {
      ['X-BFX-APIKEY'] = apikey,
      ["content-type"] = "application/json",
      ['accept']       = "application/json",
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
                          return bitfinex_authquery (self, ...)
                        end
    return new_api
  end
end

bitfinex_publicapi.tradingapi = make_apifactory (bitfinex_tradingapi)

return bitfinex_publicapi
