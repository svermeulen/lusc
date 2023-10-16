local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; require("busted")

local lusc = require('lusc')
local util = require('lusc.internal.util')
local test_async_helper = require("lusc.tests.async_helper")

local test_time_interval = 1

local function _is_instance(obj, cls)

   return getmetatable(obj).__index == cls
end

describe("lusc", function()
   it("simple sleep", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.await_sleep(test_time_interval)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
   end)

   it("cancel scope move_on_after", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.move_on_after(test_time_interval, function()
            lusc.await_sleep(2 * test_time_interval)
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
   end)

   it("cancel scope move_on_after without timeout", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.move_on_after(2 * test_time_interval, function()
            lusc.await_sleep(test_time_interval)
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
   end)

   it("cancel scope move_on_at", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.move_on_at(lusc.get_time() + test_time_interval, function()
            lusc.await_sleep(2 * test_time_interval)
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
   end)

   it("cancel scope fail_after", function()
      local start_time = test_async_helper.get_time()

      util.assert_throws(function()
         test_async_helper.run_lusc(function()
            lusc.fail_after(test_time_interval, function()
               lusc.await_sleep(2 * test_time_interval)
            end)
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
   end)

   it("cancel scope fail_at", function()
      local start_time = test_async_helper.get_time()

      util.assert_throws(function()
         test_async_helper.run_lusc(function()
            lusc.fail_at(lusc.get_time() + test_time_interval, function()
               lusc.await_sleep(2 * test_time_interval)
            end)
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
   end)

   it("_is_instance", function()
      local group = lusc.ErrorGroup.new({})

      util.assert(_is_instance(group, lusc.ErrorGroup))
      util.assert(not _is_instance(group, lusc.Task))
   end)

   it("simple sleep", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         lusc.await_sleep(test_time_interval)
         local elapsed = lusc.get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
      end)
   end)

   it("await_until", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         lusc.await_until(start_time + test_time_interval)
         local elapsed = lusc.get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
      end)
   end)

   it("simple nursery", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         local end_time = nil

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               end_time = lusc.get_time()
            end)
         end)

         util.assert(end_time - start_time >= test_time_interval and end_time - start_time < 2 * test_time_interval)
      end)
   end)

   it("tasks test_async_helper.run_lusc concurrently", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         local end_time_1 = nil
         local end_time_2 = nil

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               end_time_1 = lusc.get_time()
            end)

            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               end_time_2 = lusc.get_time()
            end)
         end)

         util.assert(end_time_1 - start_time >= test_time_interval and end_time_1 - start_time < 2 * test_time_interval)
         util.assert(end_time_2 - start_time >= test_time_interval and end_time_2 - start_time < 2 * test_time_interval)
      end)
   end)

   it("consecutive sleeps in nested nursery", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         lusc.open_nursery(function()
            lusc.await_sleep(test_time_interval)
            lusc.open_nursery(function()
               lusc.await_sleep(test_time_interval)
            end)
         end)
         local elapsed = lusc.get_time() - start_time
         util.assert(elapsed >= test_time_interval * 2 and elapsed < 3 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
      end)
   end)

   it("simple event usage", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         local num_completed = 0
         lusc.open_nursery(function(nursery)
            local event = lusc.new_event()
            util.assert(not event.is_set)
            nursery:start_soon(function()
               util.assert(not event.is_set)
               event:await()
               local elapsed = lusc.get_time() - start_time
               util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
               num_completed = num_completed + 1
            end)
            nursery:start_soon(function()
               util.assert(not event.is_set)
               event:await()
               local elapsed = lusc.get_time() - start_time
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


      test_async_helper.run_lusc(function()
         local complete_order = {}
         local schedule_order = {}

         lusc.open_nursery(function(nursery)
            local start_time = test_async_helper.get_time()
            local stop_time = start_time + test_time_interval

            nursery:start_soon(function()
               lusc.await_sleep(0.001)
               table.insert(schedule_order, 0)
               lusc.await_until(stop_time)
               table.insert(complete_order, 0)
            end)

            nursery:start_soon(function()
               table.insert(schedule_order, 1)
               lusc.await_until(stop_time)
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
      local start_time = test_async_helper.get_time()
      local received_error = nil
      local child_2_finished = false

      util.try({
         action = function()
            test_async_helper.run_lusc(function()
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

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(received_error ~= nil)
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
      util.assert(not child_2_finished)
   end)

   it("disallow use not under a lusc.test_async_helper.run_lusc", function()
      util.assert_throws(function() lusc.await_sleep(test_time_interval) end)
      util.assert_throws(function() lusc.await_until(test_async_helper.get_time() + test_time_interval) end)
      util.assert_throws(function() lusc.open_nursery(function(_) end) end)
   end)

   it("explicit cancel ends sub tasks", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         local child_2_finished = false

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               nursery.cancel_scope:cancel()
            end)
            nursery:start_soon(function()
               lusc.await_sleep(10 * test_time_interval)
            end)
         end)

         local elapsed = lusc.get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
         util.assert(not child_2_finished)
      end)
   end)

   it("explicit cancel ends direct waits", function()
      test_async_helper.run_lusc(function()
         local start_time = test_async_helper.get_time()
         local child_2_finished = false

         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
               nursery.cancel_scope:cancel()
            end)
            lusc.await_sleep(10 * test_time_interval)
         end)

         local elapsed = lusc.get_time() - start_time
         util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
         util.assert(not child_2_finished)
      end)
   end)

   it("nested nurseries", function()
      local start_time = test_async_helper.get_time()




      test_async_helper.run_lusc(function()
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

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval)
   end)

   it("parent nursery cancels child nurseries", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function(nursery1)
            nursery1:start_soon(function()
               lusc.await_sleep(test_time_interval)
               nursery1.cancel_scope:cancel()
            end)

            lusc.open_nursery(function(nursery2)
               nursery2:start_soon(function()
                  lusc.await_sleep(test_time_interval * 3)
               end)
            end)
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("timeouts cancel sub tasks", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(3 * test_time_interval)
            end)
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("move on after", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function()
            lusc.await_sleep(3 * test_time_interval)
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("move on at", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function()
            lusc.await_sleep(3 * test_time_interval)
         end, { move_on_at = start_time + test_time_interval })
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("fail after", function()
      local start_time = test_async_helper.get_time()

      util.assert_throws(function()
         test_async_helper.run_lusc(function()
            lusc.open_nursery(function()
               lusc.await_sleep(3 * test_time_interval)
            end, { fail_after = test_time_interval })
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("fail at", function()
      local start_time = test_async_helper.get_time()

      util.assert_throws(function()
         test_async_helper.run_lusc(function()
            lusc.open_nursery(function()
               lusc.await_sleep(3 * test_time_interval)
            end, { fail_at = start_time + test_time_interval })
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("awaiting after cancel triggers cancel again", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function()
            util.try({
               action = function()
                  lusc.await_sleep(test_time_interval * 2)
               end,
               finally = function()

                  lusc.await_sleep(3 * test_time_interval)
               end,
            })
         end, { move_on_after = test_time_interval })
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("move on after cancels further wait attempts after error", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
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

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("await send blocks", function()
      test_async_helper.run_lusc(function()
         local function measure_time(func)
            local start = lusc.get_time()
            func()
            return lusc.get_time() - start
         end

         lusc.open_nursery(function(nursery)
            local channel = lusc.open_channel(1)

            nursery:start_soon(function()
               local value, is_done = channel:await_receive_next()
               util.assert(not is_done)
               util.assert(value == 1)
               lusc.await_sleep(test_time_interval)
               value, is_done = channel:await_receive_next()
               util.assert(not is_done)
               util.assert(value == 2)
               value, is_done = channel:await_receive_next()
               util.assert(not is_done)
               util.assert(value == 3)
            end)

            nursery:start_soon(function()
               util.log("sending 1...")
               util.assert(measure_time(function() channel:send(1) end) < test_time_interval)
               util.assert_throws(function()
                  channel:send(2)
               end)
               util.log("sending 2...")
               util.assert(measure_time(function() channel:await_send(2) end) < test_time_interval)
               util.log("sending 3...")
               util.assert(measure_time(function() channel:await_send(3) end) >= test_time_interval)
            end)
         end)
      end)
   end)

   it("channels simple", function()
      test_async_helper.run_lusc(function()
         local received_values = {}
         local num_entries = 5

         lusc.open_nursery(function(nursery)
            local channel = lusc.open_channel()

            nursery:start_soon(function()
               channel:close_after(function()
                  for i = 1, num_entries do
                     util.log("sending %s", i)
                     channel:send(i)
                     lusc.await_sleep(0)
                  end
               end)
            end)

            nursery:start_soon(function()
               for value in channel:await_receive_all() do
                  util.log("received %s", value)
                  table.insert(received_values, value)
               end
            end)
         end)

         util.assert(#received_values == num_entries)
         for i = 1, num_entries do
            util.assert(received_values[i] == i)
         end
      end)
   end)

   it("channels with max size", function()
      test_async_helper.run_lusc(function()
         local received_values = {}
         local num_entries = 5

         lusc.open_nursery(function(nursery)
            local channel = lusc.open_channel(2)

            nursery:start_soon(function()
               channel:close_after(function()
                  for i = 1, num_entries do
                     util.log("sending %s", i)
                     channel:await_send(i)
                  end
               end)
            end)

            nursery:start_soon(function()
               for value in channel:await_receive_all() do
                  util.log("received %s", value)
                  table.insert(received_values, value)
               end
            end)
         end)

         util.assert(#received_values == num_entries)
         for i = 1, num_entries do
            util.assert(received_values[i] == i)
         end
      end)
   end)

   it("cannot used closed channel", function()
      test_async_helper.run_lusc(function()
         lusc.open_nursery(function(nursery)
            local channel = lusc.open_channel()

            nursery:start_soon(function()
               channel:close_after(function()
                  channel:send(0)
               end)
               util.assert_throws(function()
                  channel:send(1)
               end)
               util.assert_throws(function()
                  channel:close()
               end)
            end)
         end)
      end)
   end)

   it("cancel scope shielding", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.move_on_after(test_time_interval, function()
            util.try({
               action = function()
                  lusc.await_sleep(20)
               end,
               catch = function(err)
                  util.log("caught and discarded err '%s'", err)
                  lusc.cancel_scope(function()
                     util.log("awaiting again")
                     lusc.await_sleep(test_time_interval)
                     util.log("done awaiting")
                  end, { shielded = true })
                  util.log("completed shield thing")
                  lusc.await_sleep(test_time_interval)
               end,
            })
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= 2 * test_time_interval and elapsed < 3 * test_time_interval, "Found %s seconds elapsed", elapsed)
   end)

   it("move_on_after with nested nursery", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         local result = lusc.move_on_after(test_time_interval, function()
            lusc.open_nursery(function(n1)
               n1:start_soon(function()
                  lusc.await_sleep(2 * test_time_interval)
               end)
            end)
         end)

         util.assert(result.hit_deadline)
         util.assert(result.was_cancelled)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= test_time_interval and elapsed < 2 * test_time_interval, "Found %s seconds elapsed but expected %s", elapsed, test_time_interval)
   end)

   it("can await after cancel scope", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.move_on_after(test_time_interval, function()
            lusc.open_nursery(function(n2)
               n2:start_soon(function()
                  lusc.await_sleep(3 * test_time_interval)
               end)
            end)
         end)
         lusc.await_sleep(test_time_interval)
      end)

      local expected_num_waits = 2
      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= expected_num_waits * test_time_interval and elapsed < (expected_num_waits + 1) * test_time_interval, "Actual elapsed: %s (~%s)", elapsed, elapsed / test_time_interval)
   end)

   it("can cancel immediately before nursery close", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.await_sleep(2 * test_time_interval)
            end)

            nursery:start_soon(function()
               lusc.await_sleep(test_time_interval)
            end)

            nursery.cancel_scope:cancel()
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed < test_time_interval)
   end)

   it("adding new task in a cancelled nursery", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function(nursery)
            nursery.cancel_scope:cancel()

            nursery:start_soon(function()
               lusc.await_sleep(2)
            end)
         end)
      end, 1000)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed < test_time_interval)
   end)

   it("awaiting in a shield scope after cancel completes", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.move_on_after(test_time_interval, function()
            util.try({
               action = function()
                  lusc.await_sleep(2 * test_time_interval)
               end,
               finally = function()
                  lusc.cancel_scope(function()
                     lusc.await_sleep(2 * test_time_interval)
                  end, { shielded = true })
               end,
            })
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= 3 * test_time_interval and elapsed < 4 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("shielding within a nursery task works", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.open_nursery(function(nursery)
            nursery:start_soon(function()
               lusc.cancel_scope(function()
                  lusc.await_sleep(2 * test_time_interval)
               end, { shielded = true })

               lusc.await_sleep(test_time_interval)
            end)

            lusc.await_sleep(test_time_interval)
            nursery.cancel_scope:cancel()
         end)
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= 2 * test_time_interval and elapsed < 3 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("nested cancel scopes respect the cancel depth", function()
      local start_time = test_async_helper.get_time()

      test_async_helper.run_lusc(function()
         lusc.move_on_after(test_time_interval, function()
            util.try({
               action = function()
                  lusc.await_sleep(2 * test_time_interval)
               end,
               catch = function()
                  lusc.move_on_after(test_time_interval, function()
                     lusc.await_sleep(2 * test_time_interval)
                  end, { shielded = true, name = "inner scope" })
                  lusc.await_sleep(4 * test_time_interval)
               end,
            })
            lusc.await_sleep(4 * test_time_interval)
         end, { shielded = true, name = "outer scope" })
      end)

      local elapsed = test_async_helper.get_time() - start_time
      util.assert(elapsed >= 2 * test_time_interval and elapsed < 3 * test_time_interval, "Elapsed: %s", elapsed)
   end)

   it("nursery forwards multiple child errors", function()
      test_async_helper.run_lusc(function()
         util.try({
            action = function()
               lusc.open_nursery(function(nursery)
                  local trigger_time = lusc.get_time() + test_time_interval

                  nursery:start_soon(function()
                     lusc.await_until(trigger_time)
                     error('oops1')
                  end)

                  nursery:start_soon(function()
                     lusc.cancel_scope(function()
                        lusc.await_until(trigger_time)
                        error('oops2')
                     end, { shielded = true })
                  end)
               end)
            end,
            catch = function(err)
               local err_str = tostring(err)
               util.assert(err_str:find('oops1') ~= nil)
               util.assert(err_str:find('oops2') ~= nil)
            end,
         })
      end)
   end)
end)
