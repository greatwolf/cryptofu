local hmac           = require 'crypto'.hmac
local digest         = require 'crypto'.digest
local from_base64    = require 'basexx'.from_base64
local to_base64      = require 'basexx'.to_base64
local tablex         = require 'pl.tablex'
local apiquery       = require 'tools.apiquery'
local urlencode_parm = require 'tools.util'.urlencode_parm
local nonce          = require 'tools.util'.nonce
local dump = require 'pl.pretty'.dump


local apiv = "/0"
local url  = "https://api.kraken.com" .. apiv

local function kraken_authquery (self, cmd, parm)
  parm = parm or {}
  parm.nonce  = nonce ()

  local post_data = urlencode_parm (parm)
  local uri = apiv .. "/private" .. cmd
  local msg = uri .. digest ("sha256", parm.nonce .. post_data, true)
  local sig = hmac.digest ("sha512", msg, from_base64 (self.secret), true)
  self.headers['api-sign'] = to_base64 (sig)

  local res, c = apiquery.postrequest (url, "/private" .. cmd, self.headers, post_data)

  assert (c == 200 and type(res) == 'table')
  if #res.error > 0 then return nil, table.concat (res.error) end
  return res.result
end

local kraken_publicquery = function (self, cmd, parm)
  parm = urlencode_parm (parm or {})
  if #parm > 0 then
    parm = "?" .. parm
  end
  local r, c = apiquery.getrequest (url, "/public" .. cmd .. parm)
  assert (c == 200 and type(r) == 'table')
  if #r.error > 0 then return nil, table.concat (r.error) end
  return r.result
end

local get_marketsymbol
do
  local symbols = {}
  local initsymbols, getsymbols
  initsymbols = function (market1, market2)
    local res = kraken_publicquery (nil, "/AssetPairs")
    tablex.foreach (res,
                    function (v, reqsym)
                      local pair    = v.altname
                      local revpair = pair:gsub ("(%u%u%u)(%u%u%u)", "%2%1")
                      symbols[pair]    = reqsym
                      symbols[revpair] = reqsym
                    end)

    get_marketsymbol = getsymbols
    return get_marketsymbol (market1, market2)
  end

  getsymbols = function (market1, market2)
    local pair = (market1 .. market2):upper ():gsub ("BTC", "XBT")
    return symbols[pair] or pair
  end
  get_marketsymbol = initsymbols
end

local kraken_publicapi = {}
function kraken_publicapi:markethistory (market1, market2)
  local pair = get_marketsymbol(market1, market2)
  local r, errmsg = kraken_publicquery (self,
                                        "/Trades", {pair = pair})
  if not r then return r, errmsg end

  return tablex.map  (function (v)
                        v.price,     v[1] = tonumber (v[1])
                        v.amount,    v[2] = tonumber (v[2])
                        v.timestamp, v[3] = v[3]
                        tablex.clear (v, 4)
                        return v
                      end, r[pair])
end

function kraken_publicapi:orderbook (market1, market2)
  local pair = get_marketsymbol(market1, market2)
  local r, errmsg = kraken_publicquery (self,
                                        "/Depth", {pair = pair})
  if not r then return r, errmsg end

  local unpack = unpack or table.unpack
  r = r[pair]
  r.bids.price = tablex.imap (function (v)  return tonumber (v[1]) end, r.bids)
  r.asks.price = tablex.imap (function (v)  return tonumber (v[1]) end, r.asks)
  r.bids.amount = tablex.imap (function (v) return tonumber (v[2]) end, r.bids)
  r.asks.amount = tablex.imap (function (v) return tonumber (v[2]) end, r.asks)
  tablex.clear (r.bids)
  tablex.clear (r.asks)

  return r
end

local kraken_tradingapi = {}
function kraken_tradingapi:balance ()
  local r, errmsg = self.authquery ("/Balance")
  if not r then return r, errmsg end

  return tablex.map (tonumber, r)
end

function kraken_tradingapi:tradehistory (market1, market2, start_period, stop_period)
  local parm =
    {
      type = "no position",
      start = start_period,
      ['end'] = stop_period
    }
  local r, errmsg = self.authquery ("/TradesHistory", parm)
  if not r then return r, errmsg end

  local pair = get_marketsymbol(market1, market2)
  return tablex.filter (r.trades, function (v) return v.pair == pair end)
end

function kraken_tradingapi:buy (market1, market2, rate, quantity)
  local parm =
    {
      pair = get_marketsymbol(market1, market2),
      type = "buy",
      price = rate,
      volume = quantity,
      ordertype = "limit",
    }
  return self.authquery ("/AddOrder", parm)
end

function kraken_tradingapi:sell (market1, market2, rate, quantity)
  local parm =
    {
      pair = get_marketsymbol(market1, market2),
      type = "sell",
      price = rate,
      volume = quantity,
      ordertype = "limit",
    }
  return self.authquery ("/AddOrder", parm)
end

function kraken_tradingapi:cancelorder (ordernumber)
  return self.authquery ("/CancelOrder", {txid = ordernumber})
end

function kraken_tradingapi:openorders (market1, market2)
  local r, errmsg = self.authquery ("/OpenOrders",
                                    {pair = get_marketsymbol(market1, market2)})
  if not r then return r, errmsg end
  return r.open
end

local make_authself = function (apikey, apisecret)
  return
  {
    headers =
    {
      ['api-key'] = apikey,
      ["content-type"] = "application/x-www-form-urlencoded",
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
                          return kraken_authquery (self, ...)
                        end
    return new_api
  end
end

kraken_publicapi.tradingapi = make_apifactory (kraken_tradingapi)

return kraken_publicapi
