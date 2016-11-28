local heartbeat = {}

local tick_charswitch =
{
  [' '] = '.',
  ['.'] = ' '
}

local pulse_state =
{
  dead = 1,
  live = 2,
}


local function clear_pulseline (self)
  local clear_width = self.pulse_width
  local start = ('\b'):rep (clear_width)

  self.pulse_writer (start)
  self.pulse_writer ((' '):rep (clear_width))
  self.pulse_writer (start)
end

local function print_pulseline (self)
  self.pulse_writer '\n'
  self.pulse_writer (self.pulse_linestr)
  self.pulse_writer (('\b'):rep (self.pulse_width - 1))
end

function heartbeat:tick ()
  if self.pulse == pulse_state.dead then
    print_pulseline (self)
    self.pulse = pulse_state.live
  end

  self.pulse_writer (self.tick_char)
  self.cursor_sp = self.cursor_sp - 1
  if self.cursor_sp == 0 then
    self.cursor_sp = self.pulse_width - 2
    self.pulse_writer (('\b'):rep (self.cursor_sp))
    self.tick_char = tick_charswitch[self.tick_char]
  end
end

function heartbeat:clear ()
  if self.pulse == pulse_state.live then
    clear_pulseline (self)
    self.tick_char = '.'
    self.cursor_sp = self.pulse_width - 2
    self.pulse = pulse_state.dead
  end
end

local heartbeat_mt = { __index = heartbeat }
function heartbeat.newpulse (width, writer)
  assert (type(width) == "number" and width > 2)
  local self =
  {
    pulse_width = width,
    pulse_writer = writer or io.write,
    pulse = pulse_state.dead,
    tick_char = '.',
  }
  self.cursor_sp = self.pulse_width - 2
  self.pulse_linestr = ("[%s]"):format ((' '):rep (self.cursor_sp))

  return setmetatable (self, heartbeat_mt)
end

return heartbeat
