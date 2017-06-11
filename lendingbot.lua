require 'config'
local make_log    = require 'tools.logger'
local make_retry  = require 'tools.retry'
local heartbeat   = require 'tools.heartbeat'
local sleep = require 'tools.sleep'
local seq   = require 'pl.seq'
local set   = require 'pl.set'
local lapp  = require 'pl.lapp'


lapp.add_type  ('amount', tonumber,
                function (v)
                  lapp.assert (v > 0, 'amount must be > 0!')
                end)
lapp.add_type  ('seconds', tonumber,
                function (v)
                  lapp.assert (v >= 30, 'must be at least 30 seconds!')
                end)
lapp.add_type  ('minutes', tonumber,
                function (v)
                  lapp.assert (math.floor (v) > 0, 'must be at least 1 minute!')
                end)
lapp.add_type  ('int', tonumber,
                function (v)
                  lapp.assert (math.floor (v) > 1, 'int must be at > 1!')
                end)
local args = lapp
[[
Lending Bot
Usage: lendingbot [options] <exchange> <currency>

options:
  -v                        Show stacktrace on request errors.
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

  <exchange>  (bitfinex|poloniex)
  <currency>  (string)
              poloniex:
                btc, bts, clam, doge, dash, ltc, maid, str, xmr, xrp, eth, fct
              bitfinex:
                usd, btc, eth, etc, zec, xmr, ltc, dsh
]]

local check_currency = function (args)
  local exchange =
  {
    bitfinex = set {"usd", "btc", "eth", "etc", "zec", "xmr", "ltc", "dsh"},
    poloniex = set {"btc", "bts", "clam", "doge", "dash", "ltc",
                    "maid", "str", "xmr", "xrp", "eth", "fct"}
  }
  exchange = exchange[ args.exchange ]
  lapp.assert (exchange[ args.currency ], "Unsupported crypto on this exchange!")
end
check_currency (args)

local publicapi   = require ('exchange.' .. args.exchange)
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
local auth    = apikeys[args.exchange]
local lendapi = publicapi.lendingapi (auth.key, auth.secret)
local unpack = unpack or table.unpack
local retry_profile = { 3, logcrit, "HTTP/1%.1 %d+ %w+", "wantread", "closed", "timeout" }
publicapi.lendingbook = make_retry (publicapi.lendingbook, unpack (retry_profile))
lendapi.authquery     = make_retry (lendapi.authquery,     unpack (retry_profile))

local ratepip = 1E5
local function groupadjacent (precision, initial)
  local floor     = math.floor
  local lastrate  = floor (initial.rate * precision)
  initial.rate    = (lastrate - 1) / precision
  return function(curr, prev)
    local curr_rate  = floor (curr.rate * precision)
    local is_consec = curr_rate - lastrate <= 1
    lastrate  = curr_rate
    curr.rate = is_consec and prev.rate or (curr_rate - 1) / precision

    return curr
  end
end

local utc_now = function ()
  local t = os.date '!*t'; t.isdst = nil;
  return os.time (t)
end -- UTC

local scale_duration = function (rate, avg, sd)
  local e = math.exp (1)
  local zscore = (rate - avg) / sd
  local x = 4 * zscore - 8
  local sigmoid = 2 + 18 / (1 + e^-x)
  return math.floor (sigmoid + 0.5)   -- round off
end

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
            local r, errmsg = lendapi:canceloffer (v.orderid)
            local status = "%s #%s"
            return errmsg or (status:format (r.message, v.orderid))
          end)
    :foreach (function (v) log (v) end)
end

local satoshi = 1E8
local place_newoffers = function (context)
  if #context.openoffers > 0 then return end

  local newoffer_count = 5
  local seen = {}
  local lendingbook = context.lendingbook
  local balance     = math.floor (context.balance * satoshi)
  local chunk       = math.floor (lend_quantity * satoshi)

  local r =
    seq (lendingbook)
    :filter (function () return chunk <= balance end)
    :last ()
    :map (groupadjacent (ratepip, lendingbook[1]))
    :filter (function (v) return v.amount > wallfactor end)
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
            local period   = scale_duration (v.rate, context.sma, 0.015)
            local quantity = (chunk + balance % chunk) / satoshi
            log (("placing offer: %.8f @%.6f%%"):format (quantity, v.rate))
            local offerstat, errmsg = lendapi:placeoffer (crypto, v.rate, quantity, period)
            if errmsg then return errmsg end

            assert (offerstat.success == 1)
            balance = balance - quantity * satoshi

            local status = "%s #%s"
            return status:format (offerstat.message,
                                  offerstat.orderid)
          end)
    :foreach (function (v) log (v) end)
end

local function total_activeoffers (activeoffers)
  return seq (activeoffers)
          :map (function (v) return v.amount end)
          :reduce '+' or 0
end

local function compute_loanyield (context)
  local sum =
    seq (context.activeoffers)
    :map (function (v) return v.amount * v.rate end)
    :reduce '+'
  return not sum and 0 or (sum / context.lent)
end

local prev_activeid = set ()
local prev_activedetail
local function check_activeoffers (activeoffers)
  local curr_activedetail = {}
  local curr_activeid = set (seq (activeoffers)
                              :map (function (v)
                                      curr_activedetail[v.orderid] = v
                                      return v.orderid
                                    end)
                              :copy ())

  if prev_activeid == curr_activeid then return end

  local expired = set.values (prev_activeid - curr_activeid)
  seq (expired)
    :map (function (id) return assert (prev_activedetail[ id ]) end)
    :foreach (function (v)
                local status = "expired offer: #%s, %.8f @%.6f%%"
                log (status:format (v.orderid, v.amount, v.rate))
              end)
  local filled = set.values (curr_activeid - prev_activeid)
  seq (filled)
    :map (function (id) return assert (curr_activedetail[ id ]) end)
    :foreach (function (v)
                local status = "filled offer: #%s, %.8f @%.6f%%"
                log (status:format (v.orderid, v.amount, v.rate))
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
local show_yield        = log_changes (crypto .. " effective yield: %.6f%%")
local show_activecount  = log_changes "%d active loans"
local show_opencount    = log_changes "%d open offers"
local show_sma          = log_changes (args.sma_bars .. "-min SMA rate: %.6f%%")

local show_lendinginfo = function (context)
  show_activecount (#context.activeoffers)
  show_opencount (#context.openoffers)
  show_balance (context.balance)
  show_lent (context.lent)
  show_yield (context.yield)
  show_sma (context.sma)
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
  local pcall = args.v and xpcall or pcall
  repeat
    status, errmsg = pcall (task, debug.traceback)

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
  print "Lending Bot"
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
      lendingcontext.sma    = sma.compute ()
      lendingcontext.lent   = total_activeoffers (lendingcontext.activeoffers)
      lendingcontext.yield  = compute_loanyield (lendingcontext)

      check_activeoffers (lendingcontext.activeoffers)
      show_lendinginfo (lendingcontext)
  end
  local run_bot =
  {
    [relaxed] = delay (function ()
      common_actions ()
      if  #lendingcontext.openoffers > 0 or
          lend_quantity <= lendingcontext.balance then
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
