local https           = require 'ssl.https'
local json            = require 'dkjson'
local imap            = require 'pl.tablex'.imap
local update          = require 'pl.tablex'.update
local map_transpose   = require 'tools.util'.map_transpose
local urlencode_parm  = require 'tools.util'.urlencode_parm
local z               = require 'zlib' -- for gzip

local url, apiurl = "https://www.mintpal.com", "https://api.mintpal.com"
local tradefee = 0.15 / 100

socket.http.TIMEOUT = 75

-- internal querying functions for pulling data off mintpal servers
-- forward declares
local mp_query, mp_apiv2query, mp_webquery

-- mintpal helper functions
local mp_validresponse = function (resp)
  -- check response is really mintpal and not Incapsula's anti-bot page
  local count = 0
  for each in resp:gmatch "[Ii]ncapsula" do
    count = count + 1
  end
  return assert (count < 2, "response not from MintPal!") and resp
end

local mp_getmarketid
do
  local market_ids = {}
  mp_getmarketid = function (market1, market2)
    if not next (market_ids) then
      local markets = mp_apiv2query ("GET", "/market/summary/BTC").data
      for _, market in ipairs(markets) do
        local pair = "BTC_" .. market.code
        market_ids[pair] = market.market_id
      end
      markets = mp_apiv2query ("GET", "/market/summary/LTC").data
      for _, market in ipairs(markets) do
        local pair = "LTC_" .. market.code
        market_ids[pair] = market.market_id
      end
    end

    local pair = (market1 .. "_" .. market2):upper()
    return assert (market_ids[pair], "no market pair " .. pair)
  end
end

-- internal query function definitions
mp_query = function (method, headers, url, path, data)
  local resp = {}
  local r, c, h = https.request
    {
      method = method,
      url = url .. path,
      headers = headers,
      source = data and ltn12.source.string (data),
      sink = ltn12.sink.table (resp),
    }
  resp = assert(r, c) and table.concat(resp)
  if h["content-encoding"] == "gzip" then
    resp = z.inflate (resp):read "*a"
  end
  return resp
end

mp_apiv2query = function (method, urlpath, data)
  local post_headers = {connection = "keep-alive", ["accept-encoding"] = "gzip"}
  local r = mp_query (method, post_headers, apiurl .. "/v2", urlpath, data)

  return assert (json.decode (r))
end

mp_webquery = function (sessionheaders, method, path, data, extraheaders)
  local post_headers = update ({connection = "keep-alive", ["accept-encoding"] = "gzip"}, sessionheaders)
  if extraheaders then
    post_headers = update (post_headers, extraheaders)
  end

  post_headers["content-length"] = data and #data
  local r = mp_query (method, post_headers, url, path, data)
  return mp_validresponse (r)
end

-- main MintPal api functions
local mintpal_api = {}
function mintpal_api:balance ()
  local resp = self:mp_webquery ("GET", "/balances")

  local balances = {}
  for code, balance in resp:gmatch "<td>([%u%d]+)</td><td>[%w ]+</td><td><strong>(%d+[.%d]*)</strong></td>" do
    balances[code] = tonumber (balance)
  end
  balances.BTC = balances.BTC or 0
  return balances
end

function mintpal_api:tradehistory (market1, market2)
  local resp = self:mp_webquery ("GET", string.format ("/market/%s/%s", market2, market1))
  -- fetching tradehistory causes csrf_token to change.
  -- grab the new csrf_token from this response and save it.
  self:mp_updatecsrf_token (resp, market1, market2)
  -- Now search and parse the trade history
  resp = resp:match "<h2>Your Recent Trades</h2>.+<tbody>(.+)</tbody>"
  local trade_pat = [[<tr><td>([%d :-]+)</td><td><span[^\n>]+>([BS][UE][YL]L?)</span></td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td></tr>]]
  local trades = {}
  -- if no past trade history for this market pair
  -- return empty table
  if not resp then return trades end
  for date, type, rate, amount, _, _, total in resp:gmatch (trade_pat) do
    table.insert (trades, {date = date, type = type, rate = rate, amount = amount, total = total})
  end
  return trades
end

local mp_executeorder = function (self, market1, market2, action, extra_data)
  local marketid   = mp_getmarketid (market1, market2)
  local csrf_token = "csrf_token_market" .. marketid
  local data = 
  {
    [csrf_token] = self:mp_getcsrf_token {market1, market2},
    market = marketid,
  }
  data = update (data, extra_data)
  local r = self:mp_webquery ("POST", action,
                              urlencode_parm (data), {["X-Requested-With"] = "XMLHttpRequest"})
  if r:match "unknown error occurred%." then
    data[csrf_token] = self:mp_getcsrf_token {market1, market2, force_newtoken = true}
    r = self:mp_webquery ("POST", action,
                          urlencode_parm (data), {["X-Requested-With"] = "XMLHttpRequest"})
  end
  r = json.decode (r)
  if r.response ~= "success" then return nil, r.reason end
  return r
end

function mintpal_api:buy (market1, market2, rate, quantity)
  local data = 
  {
    type = 0,
    amount = quantity, price = rate,
    buyNetTotal = quantity * rate * (1 + tradefee),
  }
  
  local r, errmsg = mp_executeorder (self, market1, market2, "/action/addOrder", data)
  if not r then return r, errmsg end
  local resp = self:openorders (market1, market2)
  if resp and resp[1].time == os.date ("!%Y-%m-%d %X", r.timestamp) then
    r.orderNumber = resp[1].order_id
  end
  return r
end

function mintpal_api:sell (market1, market2, rate, quantity)
  local data = 
  {
    type = 1,
    amount = quantity, price = rate,
    sellNetTotal = quantity * rate * (1 - tradefee),
  }

  local r, errmsg = mp_executeorder (self, market1, market2, "/action/addOrder", data)
  if not r then return r, errmsg end
  local resp = self:openorders (market1, market2)
  if resp and resp[1].time == os.date ("!%Y-%m-%d %X", r.timestamp) then
    r.orderNumber = resp[1].order_id
  end
  return r
end

function mintpal_api:cancelorder (market1, market2, ordernumber)
  local data = { orderId = ordernumber, }

  return mp_executeorder (self, market1, market2, "/action/cancelOrder", data)
end

function mintpal_api:markethistory (market1, market2)
  local r = mp_apiv2query ("GET", string.format ("/market/trades/%s/%s", market2, market1))
  if r.status ~= "success" then return nil, r.message end
  return r
end

function mintpal_api:orderbook (market1, market2)
  local orderbook = {}
  local bids = mp_apiv2query ("GET", string.format ("/market/orders/%s/%s/BUY", market2, market1))
  local asks = mp_apiv2query ("GET", string.format ("/market/orders/%s/%s/SELL", market2, market1))
  if bids.status ~= "success" then return nil, bids.message end
  if asks.status ~= "success" then return nil, asks.message end

  orderbook.buy  = map_transpose (bids.data)
  orderbook.sell = map_transpose (asks.data)
  orderbook.buy.price   = imap (tonumber, orderbook.buy.price)
  orderbook.buy.amount  = imap (tonumber, orderbook.buy.amount)
  orderbook.sell.price  = imap (tonumber, orderbook.sell.price)
  orderbook.sell.amount = imap (tonumber, orderbook.sell.amount)
  orderbook.buy.total, orderbook.sell.total = nil
  return orderbook
end

function mintpal_api:openorders (market1, market2)
  local r = self:mp_webquery ("GET", "/action/getUserOrders/" .. mp_getmarketid (market1, market2), 
                              nil, {["X-Requested-With"] = "XMLHttpRequest"})
  r = json.decode (r)
  if r.response ~= "success" then return nil, r.reason end
  return r.data
end

local find_incapcookies = function (t)
  local incap_ses
  for k in pairs(t) do
    incap_ses = incap_ses or k:match "incap_ses_[%d_]+"
  end
  return incap_ses
end

mintpal_api.__index = mintpal_api
local mintpal_create = function (cookies)
  local incap_ses = find_incapcookies(cookies)
  assert (cookies.session_id and incap_ses, "Missing Mintpal cookies.")

  cookies.MintPal = cookies.session_id
  local headers =
  {
    cookie = urlencode_parm (cookies, "; "),
    ["content-type"] = "application/x-www-form-urlencoded",
    connection = "keep-alive",
  }
  local session = {}
  function session:mp_webquery (method, path, data, extraheaders)
    return mp_webquery (headers, method, path, data, extraheaders)
  end

  local csrf_tokens = {}
  function session:mp_getcsrf_token (args)
    local currencypair = (args[2] .. "/" .. args[1]):upper()
    if not csrf_tokens[currencypair] or args.force_newtoken then
      local r = self:mp_webquery ("GET", ("/market/%s/%s"):format (args[2], args[1]))
      self:mp_updatecsrf_token (r, args[1], args[2])
    end
    return csrf_tokens[currencypair]
  end
  
  function session:mp_updatecsrf_token (resp, market1, market2)
    local currencypair = (market2 .. "/" .. market1):upper()
    csrf_tokens[currencypair] = assert(resp:match "var token = '(%w+)';",
                                       "could not get csrf_token!")
  end

  return setmetatable (session, mintpal_api)
end

return mintpal_create
