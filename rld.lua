-- rld - Redis Lua Debugger
-- By: Itamar Haber, Redis Labs

local rld = {}
rld.version = "0.1.0"
rld.stack = {}
rld.fcounts = {}
rld.skip = 0

-- debugger options - can be set before starting the debugger
rld.options = { 
  trace = true,               -- traces every executed line
  calls = true,               -- traces function calls & returns
  variables = true,           -- auto-watch local variables
  medium = "*",               -- logging medium, can be: log, pub or *
  loglv = redis.LOG_WARNING,  -- redis.log log level
  verbose = false }           -- print event and traceback for every hook call to log file

-- stack manipulation functions
function rld.stackpush(f)
  rld.stack[#rld.stack+1] = { name = f, args = {}, locs = {} }
end

function rld.stackpop()
  if #rld.stack ~= 0 then
    local f = rld.stack[#rld.stack].name
    rld.stack[#rld.stack] = nil
    return f
  else
    return nil
  end
end

-- get a function's local variables
-- level: current level
function rld.getlocals (level)
  local i
  local locals = {}

  i = 1
  while true do
    local name, value = debug.getlocal(level + 1, i)
    if not name then break end
    if string.sub(name,1,1) ~= "(" then -- ignore '(*temporary)' variables
      locals[name] = value
    end
    i = i + 1
  end
  return locals
end

-- outputs messages to log mediums 
function rld.log(msg)
  if msg == nil then msg = "(nil)" end
  if rld.options.medium == "log" or rld.options.medium == "*" then
    redis.log(rld.options.loglv, "[rld] " .. string.rep("    ", #rld.stack - 1) .. msg)
  end
  if rld.options.medium == "pub" or rld.options.medium == "*" then
    redis.call("PUBLISH", "rld", msg)
  end
end

-- "pretty" print of variables
function rld.printvars(vars, pref, prev)
  if pref == nil then pref = "" end
  
  for k, v in pairs(vars) do
    local t = type(v)
    if t == "number" or t == "string" then
      if prev == nil then 
        prev = ""
      elseif prev ~= "" then
        prev = " (was " .. prev .. ")"
      end
      rld.log(pref .. "[" .. k .. "] = " .. (t == "string" and "'" or "") .. v .. (t == "string" and "'" or "") .. prev)
      prev = ""
    elseif t == "boolean" then
      if prev == nil then
        prev = ""
      else
        prev = " (was " .. (prev and "true" or "false") .. ")"
      end
      rld.log(pref .. "[" .. k .. "] is " .. (v and "true" or "false") .. prev)
    elseif t == "table" then
      rld.log(pref .. "table " .. k .. ":")
      rld.printvars(v, "  " .. k)
    else
      rld.log(pref .. "[" .. k .. "] = (" .. t .. ")")
    end
  end
end

-- analyze local variables
function rld.analyzevars(lvl)
  local tlocs = rld.getlocals(lvl+1)
  for k, v in pairs(tlocs) do
    local pv = rld.stack[#rld.stack].locs[k]
    if pv ~= nil then
      if pv ~= v then
        if rld.skip == 0 and rld.options.variables then rld.printvars({ [k] = v }, "changed ", pv) end
        rld.stack[#rld.stack].locs[k] = v
      end 
    else
      if rld.skip == 0 and rld.options.variables then rld.printvars({ [k] = v }, "new ") end
      rld.stack[#rld.stack].locs[k] = v
    end
  end
end

-- prints summary of function call counters
function rld.printsummary()
  rld.log("-- profiler summary:")
  for f, c in pairs(rld.fcounts) do
    rld.log("--   " .. f .. " called x" .. c .. " times")
  end
end

-- the hook function is called after each execution event
function rld.hook(event, line)
  local lvl = 2
  local d = debug.getinfo(lvl)

  -- get the function's name
  local fn = d.name
  if fn == nil then
    if d.what == "Lua" then
      fn = d.what .. ":" .. d.source
    else
      fn = "!!!unknown!!!"
    end
  else
    fn = d.what .. ":" .. fn
  end

  if rld.options.verbose then -- debugger's debugging
    redis.log(rld.options.loglv, "\nVERBOSE MODE" .. 
      "\nEvent: " .. event .. " Function name: " .. fn .. " Stack size: " .. #rld.stack .. 
      "\n" .. debug.traceback() .. 
      "\nVERBOSE END")
  end

  -- event logic per event type
  if event == "call" then
    if rld.skip == 0 and rld.options.calls then
      rld.log("call to function " .. fn)
    end

    -- stack and variables management
    rld.stackpush(fn)
    rld.stack[#rld.stack].args = rld.getlocals(lvl)
    rld.stack[#rld.stack].locs = rld.stack[#rld.stack].args
    if rld.skip == 0 and rld.options.calls then 
      rld.printvars(rld.stack[#rld.stack].args, "args ") 
    end

    -- update profiler statistics
    if rld.fcounts[fn] == nil then
      rld.fcounts[fn] = 1
    else
      rld.fcounts[fn] = rld.fcounts[fn] + 1
    end
  elseif event == "line" then
    if rld.skip == 0 and rld.options.trace then
      rld.log("at " .. rld.stack[#rld.stack].name .. " (line: " .. line .. ")")
    end
    rld.analyzevars(lvl)
  elseif event == "return" then
    local s = rld.stackpop()
    if rld.skip == 0 and rld.options.calls then
      rld.log("return from function " .. s)
    end
    if #rld.stack == 0 then
      rld.stop("end of script.")
    end
  end  

  if rld.skip > 0 then rld.skip = rld.skip - 1 end
end

-- stops tracing
function rld.troff()
  rld.skip = -1
end

-- starts tracing
function rld.tron()
  rld.skip = 0
end

-- can be called from debugged script to stop the debugger
function rld.stop(msg)
    rld.printsummary()
    if msg == nil then msg = "user stopped." end
    rld.log("-- rld exited: "  .. msg)
    debug.sethook()
end

-- starts the debugger
function rld.start()
  rld.stack = {}
  rld.fcounts = {}

  rld.log("-- rld v" .. rld.version .. " started")
  rld.printvars(KEYS, "KEYS")
  rld.printvars(ARGV, "ARGV")
  rld.stackpush("Lua:@user_script")
  rld.stackpush("Lua:start")
  rld.stackpush("C:sethook")
  rld.skip = 3 -- ignore sethook's return, next line and return from rld.start
  debug.sethook(rld.hook, "clr")
end

-- load rld to _G despite @antirez's blocking efforts ;)
rawset(_G, "rld", rld)
local msg = "rld v" .. rld.version .. " loaded to Redis"
rld.log("-- " .. msg)
return(msg)
