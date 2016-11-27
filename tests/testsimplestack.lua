require 'pl.app'.require_here ".."
local stack = require 'tools.simplestack'
local utest = require 'tools.unittest'

utest.group "simplestack"
{
  test_noparmcreate = function ()
    local st = stack()
    assert (st and st:empty())
  end,

  test_emptytablecreate = function ()
    local st = stack {}
    assert (st and st:empty())
  end,

  test_badcreateparm = function ()
    local status, errmsg = pcall (stack, "bad argument")
    assert (not status and errmsg)
  end,

  test_nonemptycreate = function ()
    local st = stack {24, 42}
    assert (not st:empty ())
    assert (st:size () == 2)
  end,

  test_tableholecreate = function ()
    local st = stack {23, nil, 31, 13, nil, 83}
    assert (st:size () == 4)
    assert (st:top () == 83)
  end,

  test_push2 = function ()
    local st = stack()

    local n = math.random ()
    st:push (n)
    assert (st:size () == 1)
    assert (st:top () == n)

    n = math.random ()
    st:push (n)
    assert (st:size () == 2)
    assert (st:top () == n)
  end,

  test_pop1 = function ()
    local st = stack { 18 }
    assert (not st:empty ())
    assert (st:top () == 18)

    st:pop ()
    assert (st:empty ())
    assert (st:top () == nil)
  end,

  test_pop2 = function ()
    local st = stack { 18, 39 }
    assert (st:size () == 2)
    assert (st:top () == 39)

    st:pop ()
    assert (st:size () == 1)
    assert (st:top () == 18)

    st:pop()
    assert (st:empty ())
    assert (st:top () == nil)
  end,
}

utest.run "simplestack"
