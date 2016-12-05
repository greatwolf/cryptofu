require 'pl.app'.require_here ".."
local heartbeat = require 'tools.heartbeat'
local stack     = require 'tools.simplestack'
local utest = require 'tools.unittest'

local min, max = math.min, math.max
local mock_writer
do
  local committed = stack ()
  local write_buffer, cursor
  local push_cursor = function (i)
    cursor = min (max (1, cursor + i), #write_buffer + 1)
    return cursor
  end
  local clear_buffer = function ()
    write_buffer = {}
    cursor = 1
  end
  clear_buffer ()

  local write_string = function (str)
    for c in str:gmatch '.' do
      if c == '\b' then
        push_cursor (-1)
      elseif c == '\n' then
        committed:push (table.concat (write_buffer))
        committed:push '\n'
        clear_buffer ()
      else
        write_buffer[cursor] = c
        push_cursor (1)
      end
    end
  end

  mock_writer =
  {
    write = function (...)
      if select ('#', ...) == 0 then return true end
      local head = select (1, ...)

      assert (type(head) == "string", tostring(head))
      write_string (head)
      
      return mock_writer.write (select (2, ...))
    end,

    results = function ()
      return table.concat (committed) .. table.concat (write_buffer)
    end,

    clear = function ()
      committed = stack ()
      clear_buffer ()
    end
  }
end

utest.group "heartbeat"
{
  test_newpulsetick = function ()
    mock_writer.clear ()

    local width = 10
    local beat = heartbeat.newpulse (width, mock_writer.write)
    assert (beat)

    beat:tick ()
    local actual = mock_writer.results ()
    local expected = "[.       ]"
    assert (actual == expected)
  end,

  test_defaultwriter = function ()
    mock_writer.clear ()

    local iowrite = io.write
    io.write = mock_writer.write

    local width = 5
    local beat = heartbeat.newpulse (width)

    beat:tick ()
    io.write = iowrite
    local actual = mock_writer.results ()
    local expected = "[.  ]"
    assert (actual == expected)
  end,

  test_tickclear = function ()
    mock_writer.clear ()

    local width = 4
    local beat = heartbeat.newpulse (width, mock_writer.write)
    assert (beat)

    beat:tick ()
    beat:clear ()
    local actual = mock_writer.results ()
    local expected = "    "
    assert (actual == expected)
  end,

  test_cleartick = function ()
    mock_writer.clear ()

    local width = 6
    local beat = heartbeat.newpulse (width, mock_writer.write)
    assert (beat)

    beat:clear ()
    beat:tick ()
    local actual = mock_writer.results ()
    local expected = "[.   ]"
    assert (actual == expected)
  end,

  test_linefilltick = function ()
    mock_writer.clear ()

    local width = 7
    local beat = heartbeat.newpulse (width, mock_writer.write)
    assert (beat)

    for i = 1, width - 2 do
      beat:tick ()
    end
    local actual = mock_writer.results ()
    local expected = "[.....]"
    assert (actual == expected)
  end,

  test_tickwrap = function ()
    mock_writer.clear ()

    local width = 7
    local beat = heartbeat.newpulse (width, mock_writer.write)
    assert (beat)

    for i = 1, width do
      beat:tick ()
    end
    local actual = mock_writer.results ()
    local expected = "[  ...]"
    assert (actual == expected)
  end,
}

utest.run "heartbeat"
