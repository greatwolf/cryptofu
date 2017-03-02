local ltn12   = require 'ltn12'
local https   = require 'ssl.https'
local json    = require 'dkjson'
local tablex  = require 'pl.tablex'
local z       = require 'zlib' -- for gzip

local apiquery = {}

function apiquery.getrequest(urlbase, urlpath, headers)
  urlpath = urlpath or ""
  local req_headers =
    {
      connection = "keep-alive",
      ["accept-encoding"] = "gzip",
    }
  if headers then tablex.update (req_headers, headers) end
  local resp = {}
  local r, c, h, s = https.request
    {
      method = "GET",
      url = urlbase .. urlpath,
      headers = req_headers,
      sink = ltn12.sink.table (resp),
    }
  resp = table.concat (resp)
  assert (r and c == 200, s or c)

  if h["content-encoding"] == "gzip" then
    resp = z.inflate (resp):read "*a"
  end

  local json_resp, _, errmsg = json.decode (resp)
  assert (not errmsg and json_resp, tostring (errmsg) .. ':\n\t' .. resp)
  return json_resp
end

function apiquery.postrequest(urlbase, urlpath, headers, postdata)
  urlpath = urlpath or ""
  local req_headers =
    {
      connection = "keep-alive",
      ["accept-encoding"] = "gzip",
      ["content-length"] = postdata and #postdata,
    }
  if headers then tablex.update (req_headers, headers) end
  local resp = {}
  local r, c, h, s = https.request
    {
      method = "POST",
      url = urlbase .. urlpath,
      headers = req_headers,
      source = postdata and ltn12.source.string (postdata),
      sink = ltn12.sink.table (resp),
    }
  resp = table.concat (resp)
  assert (r and c == 200, s or c)

  if h["content-encoding"] == "gzip" then
    resp = z.inflate (resp):read "*a"
  end

  local json_resp, _, errmsg = json.decode (resp)
  assert (not errmsg and json_resp, tostring (errmsg) .. ':\n\t' .. resp)
  return json_resp
end

return apiquery
