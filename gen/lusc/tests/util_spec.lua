local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local os = _tl_compat and _tl_compat.os or os; local table = _tl_compat and _tl_compat.table or table
require("busted")

local lusc = require('lusc')
local util = require('lusc.util')

local test_time_interval = 1

local function _get_time()
   return os.time()
end

local function run(entry_point)










   lusc.run({
      entry_point = entry_point,
      time_provider = function()
         return _get_time()
      end,
      sleep_handler = function(seconds)
         os.execute("sleep " .. tostring(seconds))
      end,
   })
end

describe("lusc", function()
   it("util.is_instance", function()
      local group = lusc.ErrorGroup.new({})
      util.assert(util.is_instance(group, lusc.ErrorGroup))
      util.assert(not util.is_instance(group, lusc.Task))
   end)

   it("simple sleep", function()
      run(function()
         local start_time = _get_time()
         lusc.await_sleep(test_time_interval)
         local elapsed = _get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed <= 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
      end)
   end)

   it("await_until_time", function()
      run(function()
         local start_time = _get_time()
         lusc.await_until_time(start_time + test_time_interval)
         local elapsed = _get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed <= 2 * test_time_interval)
      end)
   end)

   it("simple nursery", function()
      run(function()
         local start_time = _get_time()
         local end_time = nil

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               end_time = _get_time()
            end)
         end)

         util.assert(end_time - start_time >= test_time_interval and end_time - start_time <= 2 * test_time_interval)
      end)
   end)

   it("tasks run concurrently", function()
      run(function()
         local start_time = _get_time()
         local end_time_1 = nil
         local end_time_2 = nil

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               end_time_1 = _get_time()
            end)

            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               end_time_2 = _get_time()
            end)
         end)

         util.assert(end_time_1 - start_time >= test_time_interval and end_time_1 - start_time < 2 * test_time_interval)
         util.assert(end_time_2 - start_time >= test_time_interval and end_time_2 - start_time < 2 * test_time_interval)
      end)
   end)

   it("consecutive sleeps in nested nursery", function()
      run(function()
         local start_time = _get_time()
         lusc.open_nursery(function()
            lusc.await_sleep(test_time_interval)
            lusc.open_nursery(function()
               lusc.await_sleep(test_time_interval)
            end)
         end)
         local elapsed = _get_time() - start_time
         util.assert(elapsed >= test_time_interval * 2 and elapsed < 3 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
      end)
   end)

   it("simple event usage", function()
      run(function()
         local start_time = _get_time()
         local num_completed = 0
         lusc.open_nursery(function(nursery)
            local event = lusc.new_event()
            util.assert(not event.is_set)
            nursery:start_soon(function()
               util.assert(not event.is_set)
               event:await()
               local elapsed = _get_time() - start_time
               util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
               num_completed = num_completed + 1
            end)
            nursery:start_soon(function()
               util.assert(not event.is_set)
               event:await()
               local elapsed = _get_time() - start_time
               util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
               num_completed = num_completed + 1
            end)
            lusc.await_sleep(test_time_interval)
            util.assert(not event.is_set)
            event:set()
            util.assert(event.is_set)
         end)
         util.assert(num_completed == 2)
      end)
   end)

   it("task order matches creation order when at same time", function()


      run(function()
         local complete_order = {}
         local schedule_order = {}

         lusc.open_nursery(function(nursery)
            local start_time = _get_time()
            local stop_time = start_time + test_time_interval

            nursery:start_soon(function()
               lusc.await_sleep(0.001)
               table.insert(schedule_order, 0)
               lusc.await_until_time(stop_time)
               table.insert(complete_order, 0)
            end)

            nursery:start_soon(function()
               table.insert(schedule_order, 1)
               lusc.await_until_time(stop_time)
               table.insert(complete_order, 1)
            end)
         end)

         util.assert(complete_order[1] == 1)
         util.assert(complete_order[2] == 0)

         util.assert(schedule_order[1] == 1)
         util.assert(schedule_order[2] == 0)
      end)
   end)

   it("errors cancel other tasks", function()
      local start_time = _get_time()
      local received_error = nil
      local child_2_finished = false

      util.try({
         action = function()
            run(function()
               lusc.open_nursery(function(nursery)
                  nursery:start_soon(function()
                     lusc.await_sleep(test_time_interval)
                     error('oops')
                  end)
                  nursery:start_soon(function()
                     lusc.await_sleep(10 * test_time_interval)
                     child_2_finished = true
                  end)
               end)
            end)
         end,
         catch = function(err)
            received_error = err
         end,
      })

      local elapsed = _get_time() - start_time
      util.assert(received_error ~= nil)
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
      util.assert(not child_2_finished)
   end)

   it("disallow use not under a lusc.run", function()
      util.assert_throws(function() lusc.await_sleep(test_time_interval) end)
      util.assert_throws(function() lusc.new_event() end)
      util.assert_throws(function() lusc.await_until_time(_get_time() + test_time_interval) end)
      util.assert_throws(function() lusc.open_nursery(function(_) end) end)
   end)

   it("explicit cancel ends sub tasks", function()
      run(function()
         local start_time = _get_time()
         local child_2_finished = false

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               nursery:cancel()
            end)
            nursery:start_soon(function()
               lusc.await_sleep(10 * test_time_interval)
            end)
         end)

         local elapsed = _get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
         util.assert(not child_2_finished)
      end)
   end)

   it("explicit cancel ends direct waits", function()
      run(function()
         local start_time = _get_time()
         local child_2_finished = false

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               nursery:cancel()
            end)
            lusc.await_sleep(10 * test_time_interval)
         end)

         local elapsed = _get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
         util.assert(not child_2_finished)
      end)
   end)

   it("nested nurseries", function()
      local start_time = _get_time()




      run(function()
         lusc.open_nursery(function(nursery1)
            nursery1:start_soon(function()
               lusc.open_nursery(function(_)
                  nursery1:start_soon(function()
                     lusc.await_sleep(test_time_interval)
                  end)
                  lusc.await_sleep(test_time_interval)
               end)
            end)
         end)
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
   end)

   it("parent nursery cancels child nurseries", function()
      local start_time = _get_time()

      run(function()
         lusc.open_nursery(function(nursery1)
            nursery1:start_soon(function()
               lusc.await_sleep(test_time_interval)
               nursery1:cancel()
            end)

            lusc.open_nursery(function(nursery2)
               nursery2:start_soon(function()
                  lusc.await_sleep(test_time_interval * 3)
               end)
            end)
         end)
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("timeouts cancel sub tasks", function()
      local start_time = _get_time()

      run(function()
         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(3 * test_time_interval)
            end)
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("move on after", function()
      local start_time = _get_time()

      run(function()
         lusc.open_nursery(function()
            lusc.await_sleep(3 * test_time_interval)
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("move on at", function()
      local start_time = _get_time()

      run(function()
         lusc.open_nursery(function()
            lusc.await_sleep(3 * test_time_interval)
         end, { move_on_at = start_time + test_time_interval })
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("fail after", function()
      local start_time = _get_time()

      util.assert_throws(function()
         run(function()
            lusc.open_nursery(function()
               lusc.await_sleep(3 * test_time_interval)
            end, { fail_after = test_time_interval })
         end)
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("fail at", function()
      local start_time = _get_time()

      util.assert_throws(function()
         run(function()
            lusc.open_nursery(function()
               lusc.await_sleep(3 * test_time_interval)
            end, { fail_at = start_time + test_time_interval })
         end)
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("awaiting after cancel triggers cancel again", function()
      local start_time = _get_time()

      run(function()
         lusc.open_nursery(function()
            util.try({
               action = function()
                  lusc.await_sleep(test_time_interval * 2)
               end,
               finally = function()

                  lusc.await_sleep(4 * test_time_interval)
               end,
            })
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("move on after cancels further wait attempts after error", function()
      local start_time = _get_time()

      run(function()
         lusc.open_nursery(function()
            util.try({
               action = function()
                  lusc.await_sleep(2 * test_time_interval)
               end,
               finally = function()
                  lusc.open_nursery(function()
                     lusc.await_sleep(2 * test_time_interval)
                  end)
               end,
            })
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("awaiting in a shield scope after cancel completes", function()
      local start_time = _get_time()

      run(function()
         lusc.open_nursery(function()
            util.try({
               action = function()
                  lusc.await_sleep(2 * test_time_interval)
               end,
               finally = function()
                  lusc.open_nursery(function()
                     lusc.await_sleep(2 * test_time_interval)
                  end, { shielded = true })
               end,
            })
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = _get_time() - start_time
      util.assert(elapsed >= 3 * test_time_interval and elapsed < 4 * test_time_interval, "Elapsed: %s", elapsed)
   end)
end)
