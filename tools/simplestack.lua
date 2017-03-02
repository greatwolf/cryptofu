--[[
  Simple Stack
  
  This implements a simple stack interface using regular
  lua tables and functions for convenience.
  
  It uses the array indexing part to store elements and
  associative part for accessing stack methods.

  Any tables with 'holes' are removed on the newly created
  table stack.
]]

local tablex = require 'pl.tablex'
local tinsert, tremove = table.insert, table.remove

local simplestack = {}
local simplestack_mt = { __index = simplestack }

function simplestack.__call (self, t)
  return simplestack.new (t)
end

function simplestack.new (t)
  assert (not t or type(t) == "table")
  local self = setmetatable ({}, simplestack_mt)
  if type(t) == "table" then
    tablex.foreachi (t, function (v) tinsert (self, v) end)
  end
  return self
end

function simplestack:push (v)
  tinsert (self, v)
end

function simplestack:pop ()
  tremove (self)
end

function simplestack:top ()
  return self[#self]
end

function simplestack:size ()
  return #self
end

function simplestack:empty ()
  return self:size () == 0
end

return setmetatable (simplestack, simplestack)
