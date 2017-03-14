local crypto         = require 'crypto'
local tablex         = require 'pl.tablex'
local apiquery       = require 'tools.apiquery'
local urlencode_parm = require 'tools.util'.urlencode_parm
local nonce          = require 'tools.util'.nonce


local apiv = "/api/3"
local url  = "https://btc-e.com"

local function btce_authquery (self, cmd, parm)
  parm = parm or {}
  parm.method = cmd
  parm.nonce  = nonce ()

  local post_data = urlencode_parm (parm)
  self.headers.sign = crypto.hmac.digest ("sha512", post_data, self.secret)

  local res = apiquery.postrequest (url, "/tapi", self.headers, post_data)
  if res.error then
    -- if it's just a bad nonce, update nonce and retry
    local new_nonce = res.error:match "invalid nonce parameter; .+ should send:(%d+)"
    if new_nonce then
      nonce (new_nonce + 0)
      return btce_authquery (self, cmd, parm)
    end
  end

  return res.error and res or res['return']
end

local btce_publicquery = function (self, cmd, parm)
  parm = parm or {}

  parm = urlencode_parm (parm)
  if #parm > 0 then
    parm = "?" .. parm
  end
  local r, c = apiquery.getrequest (url .. apiv, cmd .. parm)
  assert (c == 200 and type(r) == 'table')
  if r.error then return nil, r.error end
  return r
end

local get_marketsymbol
do
  local symbols
  local initsymbols, getsymbols
  initsymbols = function (market1, market2)
    local res = btce_publicquery (nil, "/info")
    symbols = tablex.pairmap (function (_, v) return v,v end,
                              tablex.keys (res.pairs))
    get_marketsymbol = getsymbols
    return get_marketsymbol (market1, market2)
  end

  getsymbols = function (market1, market2)
    market1, market2 = market1:lower (), market2:lower ()
    local marketpair = symbols[market2 .. "_" .. market1] or
                       (market1 .. "_" .. market2)
    return marketpair
  end
  get_marketsymbol = initsymbols
end

local btce_publicapi = {}
function btce_publicapi:markethistory (market1, market2)
  local currencypair = get_marketsymbol(market1, market2)
  local r, errmsg = btce_publicquery (self,
                                      "/trades/" .. currencypair)
  if not r then return r, errmsg end

  return r[currencypair]
end

function btce_publicapi:orderbook (market1, market2)
  local currencypair = get_marketsymbol(market1, market2)
  local r, errmsg = btce_publicquery (self,
                                      "/depth/".. currencypair)
  if not r then return r, errmsg end

  local unpack = unpack or table.unpack
  r = r[currencypair]
  r.bids.price = tablex.imap (function (v) return v[1] end, r.bids)
  r.asks.price = tablex.imap (function (v) return v[1] end, r.asks)
  r.bids.amount = tablex.imap (function (v) return v[2] end, r.bids)
  r.asks.amount = tablex.imap (function (v) return v[2] end, r.asks)
  tablex.clear (r.bids)
  tablex.clear (r.asks)

  return r
end

local btce_tradingapi = {}
function btce_tradingapi:balance ()
  local r = self.authquery ("getInfo")
  if r.error then return nil, r.error end
  return r.funds
end

function btce_tradingapi:tradehistory (market1, market2, start_period, stop_period)
  local parm =
    {
      pair = get_marketsymbol(market1, market2),
      since = start_period,
      ['end'] = stop_period
    }
  local r = self.authquery ("TradeHistory", parm)
  if r.error then return nil, r.error end
  return r
end

function btce_tradingapi:buy (market1, market2, rate, quantity)
  local parm =
    {
      pair = get_marketsymbol(market1, market2),
      type = "buy",
      rate = rate,
      amount = quantity,
    }
  local r = self.authquery ("Trade", parm)
  if r.error then return nil, r.error end
  return r
end

function btce_tradingapi:sell (market1, market2, rate, quantity)
  local parm =
    {
      pair = get_marketsymbol(market1, market2),
      type = "sell",
      rate = rate,
      amount = quantity,
    }
  local r = self.authquery ("Trade", parm)
  if r.error then return nil, r.error end
  return r
end

function btce_tradingapi:cancelorder (ordernumber)
  local r = self.authquery ("CancelOrder", {order_id = ordernumber})
  if r.error then return nil, r.error end
  return r
end

function btce_tradingapi:openorders (market1, market2)
  local r = self.authquery ("ActiveOrders",
                            {pair = get_marketsymbol(market1, market2)})
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
                          return btce_authquery (self, ...)
                        end
    return new_api
  end
end

btce_publicapi.tradingapi = make_apifactory (btce_tradingapi)

return btce_publicapi
