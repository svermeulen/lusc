
local lusc <const> = require("lusc")
local util <const> = require("lusc.internal.util")

local record test_async_helper
end

function test_async_helper.get_time():number
   return os.time()
end

function test_async_helper.run_lusc(handler:function(), timeout_seconds:number)
   if timeout_seconds == nil then
      timeout_seconds = 10
   end

   util.assert(not lusc.has_started())

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
   lusc.run({
      generate_debug_names = true,
      entry_point = handler,
      time_provider = test_async_helper.get_time,
      sleep_handler = function(seconds:number)
         os.execute("sleep " .. tostring(seconds))
      end,
      deadline = {
         fail_after = timeout_seconds,
      },
   })

   util.assert(not lusc.has_started())
end

function test_async_helper.measure_time(handler:function()):number
   local start_time = lusc.get_time()
   handler()
   local end_time = lusc.get_time()
   return end_time - start_time
end

return test_async_helper
