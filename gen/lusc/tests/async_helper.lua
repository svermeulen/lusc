local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local os = _tl_compat and _tl_compat.os or os
local lusc = require("lusc")
local util = require("lusc.internal.util")

local test_async_helper = {}


function test_async_helper.get_time()
   return os.time()
end

function test_async_helper.run_lusc(handler, timeout_seconds)
   if timeout_seconds == nil then
      timeout_seconds = 10
   end

   util.assert(not lusc.has_started())











   lusc.run({
      generate_debug_names = true,
      entry_point = handler,
      time_provider = test_async_helper.get_time,
      sleep_handler = function(seconds)
         os.execute("sleep " .. tostring(seconds))
      end,
      deadline = {
         fail_after = timeout_seconds,
      },
   })

   util.assert(not lusc.has_started())
end

function test_async_helper.measure_time(handler)
   local start_time = lusc.get_time()
   handler()
   local end_time = lusc.get_time()
   return end_time - start_time
end

return test_async_helper
