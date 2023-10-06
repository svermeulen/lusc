
local lusc <const> = require("lusc")

local function main()
   print("Waiting 1 second...")
   lusc.await_sleep(1)
   print("Creating child tasks...")

   -- This will run both child tasks in parallel, so
   -- the total time will be 1 second, not 2
   lusc.open_nursery(function(nursery:lusc.Nursery)
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

   -- Note also that the nursery will block until all child tasks complete
   print("Completed all child tasks")
end

-- *********  NOTE  *********
-- Do not use this function in a real app
-- It has many limitations:
-- * os.time() does not provide sub-second precision
-- * os.execute sleep is not cross platform
--
-- Instead, you should use lusc on top of something else that
-- can provide better implementations for sleep() and time_provider
-- For eg, you can use luv here:
-- https://github.com/svermeulen/lusc_luv
local function run(entry_point:function(lusc.Nursery))
   lusc.run {
      entry_point = entry_point,
      time_provider = function():number
         return os.time()
      end,
      sleep_handler = function(seconds:number)
         os.execute("sleep " .. tostring(seconds))
      end,
   }
end

run(main)
