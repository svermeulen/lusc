-- ***********
-- NOTE
-- This file is generated!  See main.tl for the actual source code
-- ***********

local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local coroutine = _tl_compat and _tl_compat.coroutine or coroutine; local os = _tl_compat and _tl_compat.os or os
local lusc = require("lusc")

local function main()
   print("Waiting 1 second...")
   lusc.await_sleep(1)
   print("Creating child tasks...")



   lusc.open_nursery(function(nursery)
      nursery:start_soon(function()
         print("child 1 started.  Waiting 1 second...")
         lusc.await_sleep(1)
         print("Completed child 1")
      end)
      nursery:start_soon(function()
         print("Child 2 started.  Waiting 1 second...")
         lusc.await_sleep(1)
         print("Completed child 2")
      end)
   end)


   print("Completed all child tasks")
end











local function run(entry_point)
   lusc.run({
      entry_point = entry_point,
      time_provider = function()
         return os.time()
      end,
      sleep_handler = function(seconds)
         os.execute("sleep " .. tostring(seconds))
      end,
   })
end

run(main)
