require 'pl.app'.require_here ".."
local logbuilder = require 'tools.logger'
local utest = require 'unittest'

local mock_writer
mock_writer = 
{
  write = function (self, str)
    mock_writer.result = mock_writer.result .. str
    return true
  end,
  clear = function (self)
    mock_writer.result = ""
  end,
  result = ""
}

local result_str = function (name, str)
  return string.format ("[%s] %s %s\n", 
                        os.date "%m-%d %H:%M:%S", name, str)
end

utest.group "logger"
{
  test_logwithcustomwriter = function ()
    mock_writer:clear ()
    local l = logbuilder ("test_log", mock_writer)
    l "foobar log"

    local result = result_str ("test_log:", "foobar log")
    assert (mock_writer.result == result)
  end,

  test_logwithdefaultwriter = function ()
    mock_writer:clear ()
    -- hook into io.stdout.write so output
    -- can be checked
    local stdout_mt = getmetatable (io.stdout).__index
    old_iowrite, stdout_mt.write = stdout_mt.write, mock_writer.write
    local l = logbuilder "test_log"
    l "foobar log"
    -- restore original io.stdout.write after testing
    stdout_mt.write = old_iowrite

    local result = result_str ("test_log:", "foobar log")
    assert (mock_writer.result == result)
  end,

  test_condtruelog = function ()
    mock_writer:clear ()
    local l = logbuilder ("test_log", mock_writer)
    l._if (true, "foobar log")

    local result = result_str ("test_log:", "foobar log")
    assert (mock_writer.result == result)
  end,

  test_condfalselog = function ()
    mock_writer:clear ()
    local l = logbuilder ("test_log", mock_writer)
    l._if (false, "foobar log")

    assert (mock_writer.result == "")
  end,
  
  test_namelesslog = function ()
    mock_writer:clear ()
    local l = logbuilder (nil, mock_writer)
    l "foobar log"
    
    local result = result_str ("", "foobar log")
    assert (mock_writer.result == result)
  end,
}

utest.run "logger"
