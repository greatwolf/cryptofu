require 'luarocks_path'
require 'pl.app'.require_here ".."
local make_retry = require 'tools.retry'
local utest = require 'unittest'

utest.group "retrywrap"
{
  test_retryfunc = function ()
    local retry_count = 0
    local f = function ()
      retry_count = retry_count + 1
      return (assert (retry_count == 2, "some error"))
    end
    
    local f_wrapped = make_retry (f, 2, "some error")
    f_wrapped ()
    assert (retry_count == 2)
  end,

  test_retrytable = function ()
    local r1, r2 = 0, 0
    local t =
    {
      func1 = function () r1 = r1 + 1; assert (r1 == 2, "an error") end,
      func2 = function () r2 = r2 + 1; assert (r2 == 2, "an error") end,
    }

    local t_wrapped = make_retry (t, 2, "an error")
    t_wrapped.func1 ()
    t_wrapped.func2 ()
    assert (r1 == 2)
    assert (r2 == 2)
  end,

  test_retrymultireason = function ()
    local r = 0
    local t =
    {
      func = function ()
        local errlist = { "error1", "error2" }
        r = r + 1
        assert (r == 3, errlist[r])
      end,
    }

    local t_wrapped = make_retry (t, 3, "error1", "error2")
    t_wrapped.func ()
    assert (r == 3)
  end,

  test_retrynestedexhaust = function ()
    local r = 0
    local t = 
    { 
      func1 = function (self) self.func2() end,
      func2 = function () r = r + 1; error "some error" end
    }
    local t_wrapped = make_retry (t, 3, "some error")
    local noerr, errmsg = pcall (t_wrapped.func1, t_wrapped)
    assert (not noerr)
    assert (r == 3, r)
  end,
}

utest.run "retrywrap"
