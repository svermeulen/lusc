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
   local pending_jobs = { entry_point }
   local coro = lusc.run({
      time_provider = function()
         return os.time()
      end,
   })

   while true do
      local ok, result = coroutine.resume(coro, pending_jobs)
      pending_jobs = {}

      if not ok then
         error(result)
      end

      if result == lusc.NO_MORE_TASKS_SIGNAL then
         break
      end

      local seconds = result
      os.execute("sleep " .. tostring(seconds))
   end
end

run(main)
