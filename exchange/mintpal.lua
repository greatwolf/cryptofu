local https = require 'ssl.https'
local json = require 'dkjson'
local foreachi = require 'pl.tablex'.foreachi
local util = require 'util'

local urlencode_parm, log = util.urlencode_parm, util.log
local url, apiurl = "https://www.mintpal.com", "https://api.mintpal.com"
local tradefee = 0.15 / 100

socket.http.TIMEOUT = 3

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
  return assert (count < 2, "response not from MintPal!")
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
  assert(r, c)
  return table.concat(resp)
end

mp_apiv2query = function (method, urlpath, data)
  local r = mp_query (method, nil, apiurl .. "/v2", urlpath, data)

  return assert (json.decode (r))
end

mp_webquery = function (sessionheaders, method, path, data, extraheaders)
  local post_headers = {}
  for k, v in pairs (sessionheaders) do post_headers[k] = v end
  if extraheaders then
    for k, v in pairs (extraheaders) do post_headers[k] = v end
  end

  post_headers["content-length"] = data and #data
  local r = mp_query (method, post_headers, url, path, data)
  mp_validresponse (r)

  return r
end

-- main MintPal api functions
local mintpal_api = {}
function mintpal_api:balance ()
  local resp = self:mp_webquery ("GET", "/balances")

  local balances = {}
  for code, balance in resp:gmatch "<td>([%u%d]+)</td><td><strong>(%d+[.%d]*)</strong></td>" do
    balances[code] = tonumber (balance)
  end
  balances.BTC = balances.BTC or 0
  return balances
end

function mintpal_api:tradehistory (market1, market2)
  local resp = self:mp_webquery ("GET", string.format ("/market/%s/%s", market2, market1))
  resp = resp:match "<h2>Your Recent Trades</h2>.+<tbody>(.+)</tbody>"
  local trade_pat = [[<tr><td>([%d :-]+)</td><td>([BS][UE][YL]L?)</td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td><td>(%d+%.?%d*)</td></tr>]]
  local trades = {}
  -- if no past trade history for this market pair
  -- return empty table
  if not resp then return trades end
  for date, type, rate, amount, _, _, total in resp:gmatch (trade_pat) do
    table.insert (trades, {date = date, type = type, rate = rate, amount = amount, total = total})
  end
  return trades
end

function mintpal_api:buy (market1, market2, rate, quantity)
  local data = 
  {
    csrf_token = self:mp_getcsrf_token (),
    ["type"] = 0,
    market = mp_getmarketid (market1, market2),
    amount = quantity,
    price = rate,
    buyNetTotal = quantity * rate * (1 + tradefee),
  }
  local r = self:mp_webquery ("POST", "/action/addOrder", 
                              urlencode_parm (data), {["X-Requested-With"] = "XMLHttpRequest"})
  r = json.decode (r)
  return assert (r.response == "success", r.reason) and r
end

function mintpal_api:sell (market1, market2, rate, quantity)
  local data = 
  {
    csrf_token = self:mp_getcsrf_token (),
    ["type"] = 1,
    market = mp_getmarketid (market1, market2),
    amount = quantity,
    price = rate,
    sellNetTotal = quantity * rate * (1 - tradefee),
  }
  local r = self:mp_webquery ("POST", "/action/addOrder", 
                              urlencode_parm (data), {["X-Requested-With"] = "XMLHttpRequest"})
  r = json.decode (r)
  return assert (r.response == "success", r.reason) and r
end

function mintpal_api:cancelorder (market1, market2, ordernumber)
  local data = 
  {
    csrf_token = self:mp_getcsrf_token (),
    orderId = ordernumber,
  }
  local r = self:mp_webquery ("POST", "/action/cancelOrder", 
                              urlencode_parm (data), {["X-Requested-With"] = "XMLHttpRequest"})
  r = json.decode (r)
  return assert (r.response == "success", r.reason) and r
end

function mintpal_api:markethistory (market1, market2)
  return mp_apiv2query ("GET", string.format ("/market/trades/%s/%s", market2, market1))
end

function mintpal_api:orderbook (market1, market2)
  local orderbook = 
  {
    buy = { price = {}, amount = {} }, sell = { price = {}, amount = {} }
  }
  local bids = mp_apiv2query ("GET", string.format ("/market/orders/%s/%s/BUY", market2, market1))
  local asks = mp_apiv2query ("GET", string.format ("/market/orders/%s/%s/SELL", market2, market1))
  assert (bids.status ~= "error", bids.message)
  assert (asks.status ~= "error", asks.message)
  
  local function accum (order, _, orderbook)
    table.insert (orderbook.price, tonumber (order.price))
    table.insert (orderbook.amount, tonumber (order.amount))
  end
  foreachi (bids.data, accum, orderbook.buy)
  foreachi (asks.data, accum, orderbook.sell)
  return orderbook
end

function mintpal_api:openorders (market1, market2)
  local r = self:mp_webquery ("GET", "/action/getUserOrders/" .. mp_getmarketid (market1, market2), 
                              nil, {["X-Requested-With"] = "XMLHttpRequest"})
  r = json.decode (r)
  return assert (r.response == "success", r.reason) and r
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

  local csrf_tokentime, csrf_token = os.clock()
  function session:mp_getcsrf_token ()
    if csrf_token and csrf_tokentime + 8 > os.clock() then return csrf_token end
    print "getting new csrf_token"
    local r = self:mp_webquery ("GET", "/profile")
    csrf_token = assert(r:match 'name="csrf_token" value="(%w+)"', "could not get csrf_token!")
    csrf_tokentime = os.clock()
    return csrf_token
  end

  return setmetatable (session, mintpal_api)
end

return mintpal_create
