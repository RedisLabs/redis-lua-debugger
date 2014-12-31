redis-lua-debugger
==================
rld is a non-interactive debugger for Lua scripts running in Redis. rld's features include:
- Easy & native installation, only ~6KB payload.
- Prints output to local and remote consoles.
- Traces the execution of code lines.
- State-of-the-art automatic watch mechanism reports new variables and value changes
- Reports function calls, returns and arguments and does on-the-fly profiling.

Basic usage
-----------
 1. Load rld.lua to Redis once (e.g. `redis-cli --eval rld.lua`).
 2. Add this line at the beginning of your Lua script: `rld.start()`.
 3. Run your code as usual (e.g. `redis-cli --eval prog.lua`).
 4. View rld's output in Redis' log file or by subscribing to the `rld` channel.

API
---
- `rld.start()` - starts the debugger
- `rld.stop()` - stops the debugger
- `rld.troff()` / `rld.tron()` - toggles tracing off/on
- `rld.options` - debugger options, see source for details

TODO
----
- Instead of auto-watch, watch explicit variables by regex (i.e. default is `.*`)
- Publish to different channels according to topic (trace, variables,...)
- Add options arguments to start()

Known Issues
------------
- Last line of user script doesn't trigger auto-watch change printouts
- Function names are shown without global context (e.g. `redis.call` becomes `call`)
- rld functions are also traced (e.g. calling rld.stop/troff/tron from @user_script)

Contributing
------------
 1. Fork it.
 2. Change it.
 3. Make a pull request.
 
License
-------
See the `LICENSE` file.

DISCLAIMER
----------
This script is highly experimental - use at your own risk!
