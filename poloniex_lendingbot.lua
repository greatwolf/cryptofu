require 'config'
local publicapi   = require 'exchange.poloniex'
local make_log    = require 'tools.logger'
local make_retry  = require 'tools.retry'
local heartbeat   = require 'tools.heartbeat'
local sleep = require 'tools.sleep'
local seq   = require 'pl.seq'
local set   = require 'pl.set'
local lapp  = require 'pl.lapp'


lapp.add_type  ('amount', 'number',
                function (v)
                  lapp.assert (v > 0, 'amount must be > 0!')
                end)
lapp.add_type  ('seconds', 'number',
                function (v)
                  lapp.assert (v >= 30, 'must be at least 30 seconds!')
                end)
lapp.add_type  ('minutes', 'number',
                function (v)
                  lapp.assert (math.floor (v) > 0, 'must be at least 1 minute!')
                end)
lapp.add_type  ('int', 'number',
                function (v)
                  lapp.assert (math.floor (v) > 0, 'int must be at > 0!')
                end)
local args = lapp
[[
Poloniex Lending Bot
Usage: poloniex_lendingbot [options] <currency>

options:
  --frontrun (amount)       Frontrun other offers w/ at least this amount.
  --quantity (amount)       Amount to lend out per offer.
  --minrate  (default 0.0)  Minimum rate the bot will lend at.
  --offerttl (seconds default 180)
                            Seconds to keep offers alive for before the bot
                            cancels and repositions.
  --sma-bars (minutes default 1)
                            Timeframe of each bar to use for simple moving average.
  --sma-length (int default 10)
                            Number of bars to use for simple moving average.

  <currency> (btc|bts|clam|doge|dash|ltc|maid|str|xmr|xrp|eth|fct)
]]

local make_clearlog = function (logname, beat)
  local logger = make_log (logname)
  return function (...)
    beat:clear ()
    return logger (...)
  end
end

local hwidth  = 79
local pulse   = heartbeat.newpulse (hwidth)
local log     = make_clearlog ("LENDBOT", pulse)
local loginfo = make_clearlog ("INFO", pulse)
local logcrit = make_clearlog ("CRITICAL", pulse)
local auth    = apikeys.poloniex
local lendapi = publicapi.lendingapi (auth.key, auth.secret)
local unpack = unpack or table.unpack
local retry_profile = { 3, logcrit, "HTTP/1%.1 %d+ %w+", "wantread", "closed", "timeout" }
publicapi.lendingbook = make_retry (publicapi.lendingbook, unpack (retry_profile))
lendapi.authquery     = make_retry (lendapi.authquery,     unpack (retry_profile))

local ratepip = 1E6
local function markgaps (initial)
  local lastseen = initial * ratepip
  local gapcount
  return function(v)
    local rate = v.rate * ratepip

    -- difference between two consecutive rates is 1 satoshi apart
    -- reset gapcount back to 0 if more than 1 satoshi apart
    gapcount = ((rate - lastseen == 1) and gapcount or 0) + 1
    v.gap = gapcount
    lastseen = rate
    return v
  end
end

local utc_now = function ()
  local t = os.date '!*t'; t.isdst = nil;
  return os.time (t)
end -- UTC

local lend_quantity = args.quantity
local wallfactor    = args.frontrun
local minrate       = math.max (args.minrate, 0)
local offerttl      = args.offerttl
local crypto        = args.currency:upper ()
local cancel_openoffers = function (context)
  local openoffers  = context.openoffers
  local r =
    seq (openoffers)
    :filter  (function (v)
                return (utc_now () - v.date) > offerttl
              end)
    :map (function (v)
            sleep (250)
            log (("cancelling offer: %.8f @%.6f%%"):format (v.amount, v.rate))
            local r, errmsg = lendapi:canceloffer (v.id)
            local status = "%s #%s"
            return errmsg or (status:format (r.message, v.id))
          end)
    :foreach (function (v) log (v) end)
end

local place_newoffers = function (context)
  if #context.openoffers > 0 then return end

  local newoffer_count = 5
  local seen = {}
  local lendingbook = context.lendingbook

  local r =
    seq (lendingbook)
    :filter (function () return context.balance > lend_quantity end)
    :map (markgaps (lendingbook[1].rate))
    :filter (function (v) return v.amount > wallfactor end)
    :map (function (v)
            v.rate = v.rate * ratepip - v.gap
            v.rate = v.rate / ratepip
            v.gap = nil
            return v
          end)
    :filter  (function (v)
                local unique = not seen[v.rate]
                seen[v.rate] = true

                return unique
              end)
    :filter (function (v) return v.rate > context.sma end)
    :filter (function (v) return v.rate > minrate end)
    :take (newoffer_count)
    :map (function (v)
            sleep (250)
            log (("placing offer: %.8f @%.6f%%"):format (lend_quantity, v.rate))
            local offerstat, errmsg = lendapi:placeoffer (crypto, v.rate, lend_quantity)
            if errmsg then return errmsg end

            assert (offerstat.success == 1)
            context.balance = context.balance - lend_quantity

            local status = "%s #%s"
            return status:format (offerstat.message,
                                  offerstat.orderID)
          end)
    :map (function (v)
            log (v)
            return v
          end)
    :copy ()

  -- only log this if there's at least one new order placed
  seq (r)
  :take (1)
  :foreach (function ()
              local msg = "%d-min SMA rate: %.6f%%"
              loginfo (msg:format (args.sma_bars, context.sma))
            end)
end

local function total_activeoffers (activeoffers)
  return seq (activeoffers)
          :map (function (v) return v.amount end)
          :reduce '+'
end

local prev_activeid = set ()
local prev_activedetail
local function check_activeoffers (activeoffers)
  local curr_activedetail = {}
  local curr_activeid = set (seq (activeoffers)
                              :map (function (v)
                                      curr_activedetail[v.id] = v
                                      return v.id
                                    end)
                              :copy ())

  if prev_activeid == curr_activeid then return end

  local expired = set.values (prev_activeid - curr_activeid)
  seq (expired)
    :map (function (id) return assert (prev_activedetail[ id ]) end)
    :foreach (function (v)
                local status = "expired offer: #%s, %.8f @%.6f%%"
                log (status:format (v.id, v.amount, v.rate))
              end)
  local filled = set.values (curr_activeid - prev_activeid)
  seq (filled)
    :map (function (id) return assert (curr_activedetail[ id ]) end)
    :foreach (function (v)
                local status = "filled offer: #%s, %.8f @%.6f%%"
                log (status:format (v.id, v.amount, v.rate))
              end)

  prev_activeid = curr_activeid
  prev_activedetail = curr_activedetail
end

local function log_changes (strfmt)
  local val
  return function (curr_val)
    if val ~= curr_val then
      val = curr_val
      loginfo (strfmt:format (val))
    end
  end
end

local show_balance      = log_changes (crypto .. " balance: %.8f")
local show_lent         = log_changes (crypto .. " lent: %.8f")
local show_activecount  = log_changes "%d active loans"
local show_opencount    = log_changes "%d open offers"

local show_lendinginfo = function (context)
  show_balance (context.balance)
  show_lent (context.lent)
  show_activecount (#context.activeoffers)
  show_opencount (#context.openoffers)
end

local make_sma = function (timeframe, length)
  local floor = math.floor
  local sma_buffer = { 0 }
  local n = 1
  local last = floor (os.time () / timeframe)
  return
  {
    update = function (value)
      assert (type(value) == 'number')
      local current = floor (os.time () / timeframe)
      if current - last > 0 then
        last = current
        n = (n % length) + 1
        sma_buffer[n] = value
      else
        sma_buffer[n] = math.max(value, sma_buffer[n])
      end
    end,

    compute = function ()
      return seq (sma_buffer):reduce '+' / #sma_buffer
    end,
  }
end

local seconds = 1E3
local function just_now () return os.clock () * seconds end

local function app_loop (func, throttle_delay)
  local start, elapse
  local task = function ()
    start = just_now ()
    func ()
    elapse = just_now () - start

    if throttle_delay > elapse then
      local sleep_delay = throttle_delay - elapse
      assert (0 < sleep_delay and sleep_delay <= throttle_delay,
              '0 < '.. sleep_delay .. ' <= ' .. throttle_delay)
      sleep (sleep_delay)
    end
    pulse:tick ()
  end

  local status, errmsg
  local quit_func
  repeat
    status, errmsg = xpcall(task, debug.traceback)

    if not status then
      quit_func = errmsg:match "interrupted!"
      logcrit (quit_func and "got quit signal!" or errmsg)
    end
  until quit_func
end

local function delay (f, msec)
  local last_run = -msec
  return function (...)
    local now = just_now ()
    local elapse = now - last_run
    if elapse < msec then return end

    last_run = now
    return f (...)
  end
end

local function bot ()
  print "Poloniex Lending Bot"
  local lendingcontext = {}
  local relaxed, lively = 1, 2
  local state = relaxed
  local sma = make_sma (60 * args.sma_bars, args.sma_length)
  local common_actions = function ()
      lendingcontext.lendingbook    = assert (publicapi:lendingbook (crypto))
      lendingcontext.openoffers     = assert (lendapi:openoffers (crypto))
      lendingcontext.activeoffers   = assert (lendapi:activeoffers (crypto))
      lendingcontext.balance        = assert (lendapi:balance ())[crypto]

      sma.update (lendingcontext.lendingbook[1].rate)
      lendingcontext.sma  = sma.compute ()
      lendingcontext.lent = total_activeoffers (lendingcontext.activeoffers)

      check_activeoffers (lendingcontext.activeoffers)
      show_lendinginfo (lendingcontext)
  end
  local run_bot =
  {
    [relaxed] = delay (function ()
      common_actions ()
      if  #lendingcontext.openoffers > 0 or
          lendingcontext.balance > lend_quantity then
        state = lively
        log "looking alive!"
      end
    end, 30*seconds),

    [lively] = delay (function ()
      common_actions ()
      if  #lendingcontext.openoffers == 0 and
          lendingcontext.balance < lend_quantity then
        state = relaxed
        log "relaxing..."
        return
      end
      cancel_openoffers (lendingcontext)
      place_newoffers (lendingcontext)
    end, 7*seconds),
  }

  return function () run_bot[state] () end
end


local main = function () app_loop (bot(), 0.5*seconds) end
main ()

log 'quitting...'
