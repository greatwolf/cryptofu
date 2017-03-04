local apiquery       = require 'tools.apiquery'
local urlencode_parm = require 'tools.util'.urlencode_parm
local tablex = require 'pl.tablex'
local dump = require 'pl.pretty'.dump

local apiv = "/v2"
local url = "https://api.bitfinex.com" .. apiv

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

    if symbols[market1 .. market2] then return market1 .. market2 end
    if symbols[market2 .. market1] then return market2 .. market1 end
    return false
  end
  get_marketsymbol = initsymbols
end

local bitfinex_publicapi = {}

function bitfinex_publicapi:orderbook (market1, market2)
  local cmd = "/book/t%s/P0"
  local sym = get_marketsymbol (market1, market2) or ""
  return bitfinex_publicquery (self, cmd:format (sym))
end

function bitfinex_publicapi:markethistory (market1, market2)
  local cmd = "/trades/t%s/hist"
  local sym = get_marketsymbol (market1, market2) or ""
  return bitfinex_publicquery (self, cmd:format (sym))
end

function bitfinex_publicapi.tradingapi (key, secret)
  return {}
end

return bitfinex_publicapi
