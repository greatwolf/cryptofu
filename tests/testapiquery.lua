require 'pl.app'.require_here ".."
local utest     = require 'tools.unittest'
local apiquery  = require 'tools.apiquery'


local host = "httpbin.org"
local url = "https://" .. host

utest.group "apiquery"
{
  test_simplegetrequest = function ()
    local r = apiquery.getrequest (url, "/get")
    assert (r and r.url)
    assert (r.url == url .. "/get")
  end,

  test_extraheaderget = function ()
    local r = apiquery.getrequest (url, "/get", { Sign = "foobar" })
    assert (r and r.headers)
    assert (r.headers.Host == host)
    assert (r.headers.Sign == "foobar")
  end,

  test_gzipget = function ()
    local r = apiquery.getrequest (url, "/gzip")
    assert (r and r.gzipped)
    assert (r.method == "GET")
  end,

  test_nonjsongetresponse = function ()
    local r, errmsg = pcall (apiquery.getrequest, url, "/xml")
    assert (not r and errmsg)
    assert (errmsg:match "value expected at line %d")
  end,

  test_badgetresponse = function ()
    local r, errmsg = pcall (apiquery.getrequest, url, "/status/404")
    assert (not r and errmsg)
    assert (errmsg:match "404 NOT FOUND", errmsg)
  end,

  test_badhostget = function ()
    local r, errmsg = pcall (apiquery.getrequest, "https://localhost")
    assert (not r and errmsg)
    assert (errmsg:match "connection refused", errmsg)
  end,

  test_simplepostrequest = function ()
    local r = apiquery.postrequest (url, "/post")
    assert (r.url)
    assert (r.url == url .. "/post")
  end,

  test_extraheaderpost = function ()
    local r = apiquery.postrequest (url, "/post", { Sign = "foobar" })
    assert (r and r.headers)
    assert (r.headers.Host == host)
    assert (r.headers.Sign == "foobar")
  end,

  test_extrapostdata = function ()
    local r = apiquery.postrequest (url, "/post", nil, "foobarbaz")
    assert (r and r.data)
    assert (r.data == "foobarbaz")
  end,

  test_badpostresponse = function ()
    local r, errmsg = pcall (apiquery.postrequest, url, "/xml")
    assert (not r and errmsg)
    assert (errmsg:match "405 METHOD NOT ALLOWED", errmsg)
  end,
}

utest.run "apiquery"
