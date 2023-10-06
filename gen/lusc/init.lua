local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local coroutine = _tl_compat and _tl_compat.coroutine or coroutine; local debug = _tl_compat and _tl_compat.debug or debug; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table









local util = require("lusc.util")

local task_counter = 0
local nursery_counter = 0

local _TASK_PAUSE = setmetatable({}, { __tostring = function() return '<task_pause>' end })
local _NO_ERROR = setmetatable({}, { __tostring = function() return '<no_error>' end })
local _CANCELLED = setmetatable({}, { __tostring = function() return '<cancelled>' end })

local lusc = {Opts = {}, ErrorGroup = {}, Task = {Opts = {}, }, Event = {}, Nursery = {Opts = {}, Result = {}, }, _Runner = {}, }





























































































































local function _log(format, ...)
   if not util.is_log_enabled() then
      return
   end

   local current_task = lusc._current_runner:_try_get_running_task()
   local message

   if current_task == nil then
      message = string.format(format, ...)
   else
      message = string.format("[%s] " .. format, current_task._debug_task_tree, ...)
   end

   util.log(message)
end



function lusc.ErrorGroup.new(errors)
   local adjusted_errors = {}

   local has_added_cancel = false


   local function add_error(err)
      if err == _CANCELLED then
         if not has_added_cancel then
            has_added_cancel = true
            table.insert(adjusted_errors, err)
         end
      else
         table.insert(adjusted_errors, err)
      end
   end




   for _, err in ipairs(errors) do
      if util.is_instance(err, lusc.ErrorGroup) then
         for _, sub_error in ipairs((err).errors) do
            util.assert(not util.is_instance(sub_error, lusc.ErrorGroup))
            add_error(sub_error)
         end
      else
         add_error(err)
      end
   end

   return setmetatable(
   {
      errors = adjusted_errors,
   },
   { __index = lusc.ErrorGroup })
end

function lusc.ErrorGroup:__tostring()
   local lines = {}
   for _, err in ipairs(self.errors) do
      table.insert(lines, tostring(err))
   end
   return table.concat(lines, '\n')
end



function lusc.Event.new(runner)
   return setmetatable(
   {
      _runner = runner,
      is_set = false,
      _waiting_tasks = {},
   },
   { __index = lusc.Event })
end

function lusc.Event:set()
   if not self.is_set then
      self.is_set = true
      for _, task in ipairs(self._waiting_tasks) do
         self._runner:_reschedule(task)
      end
   end
end

function lusc.Event:await()
   if not self.is_set then
      table.insert(self._waiting_tasks, self._runner:_get_running_task())
      self._runner:_await_task_rescheduled()
   end
end



function lusc.Task.new(runner, task_handler, nursery_owner, wait_until, opts)
   util.assert(wait_until ~= nil)
   util.assert(runner ~= nil)
   util.assert(task_handler ~= nil)

   task_counter = task_counter + 1

   local parent_task
   if nursery_owner == nil then
      parent_task = nil
   else
      parent_task = nursery_owner._task
   end

   return setmetatable(
   {
      _id = task_counter,
      _coro = coroutine.create(task_handler),
      _opts = opts or {},
      _last_schedule_time = nil,
      _runner = runner,
      _parent_task = parent_task,
      _is_paused = false,
      _done = lusc.Event.new(runner),
      _nursery_owner = nursery_owner,
      _debug_task_tree = nil,
      _child_nursery_stack = {},
      _wait_until = wait_until,
      _pending_errors = {},
      _debug_nursery_tree = nil,
   },
   { __index = lusc.Task })
end

function lusc.Task:initialize()
   local name = self._opts.name

   if name == nil then
      if self._runner._opts.generate_debug_names then
         name = string.format('t%s', self._id)
      else
         name = '<task>'
      end
   end

   if self._runner._opts.generate_debug_names and self._parent_task ~= nil then
      self._debug_task_tree = self._parent_task._debug_task_tree .. "." .. name
   else
      self._debug_task_tree = name
   end

   if self._nursery_owner == nil then
      self._debug_nursery_tree = nil
   else
      self._debug_nursery_tree = self._nursery_owner._debug_nursery_tree
   end

   _log("Created task [%s] in nursery [%s]", self._debug_task_tree, self._debug_nursery_tree)
end

function lusc.Task:_try_get_current_nursery()
   local stack = self._child_nursery_stack

   if #stack == 0 then

      if self._nursery_owner == nil then
         return nil
      end

      return self._nursery_owner
   end

   return stack[#stack]
end

function lusc.Task:_pop_pending_errors()
   local result = self._pending_errors
   self._pending_errors = {}
   return result
end

function lusc.Task:_enqueue_pending_error(err)
   table.insert(self._pending_errors, err)


   if not self._is_paused and not self._runner._pending_error_tasks_set[self] then



      table.insert(self._runner._pending_error_tasks, self)
      self._runner._pending_error_tasks_set[self] = true
   end
end

function lusc.Task:_has_pending_errors()
   return #self._pending_errors > 0
end



function lusc.Nursery.new(runner, task, opts)
   util.assert(task ~= nil)

   nursery_counter = nursery_counter + 1

   return setmetatable(
   {
      _id = nursery_counter,
      _runner = runner,
      _task = task,
      _opts = opts or {},
      _child_tasks = {},
      _child_nurseries = {},
      _cancel_requested = false,
      _cancel_requested_from_deadline = false,
      _debug_task_tree = task._debug_task_tree,
      _deadline = nil,
      _is_closed = false,
      _should_fail_on_deadline = nil,
      _deadline_task = nil,
      _debug_nursery_tree = nil,
      _parent_nursery = nil,
   },
   { __index = lusc.Nursery })
end

function lusc.Nursery:initialize()
   util.assert(not self._is_closed)

   local name = self._opts.name

   if name == nil then
      if self._runner._opts.generate_debug_names then
         name = string.format('n%s', self._id)
      else
         name = '<nursery>'
      end
   end

   local task_nursery_stack = self._task._child_nursery_stack

   if #task_nursery_stack == 0 then
      self._parent_nursery = self._task._nursery_owner
   else
      self._parent_nursery = task_nursery_stack[#task_nursery_stack]
   end

   table.insert(task_nursery_stack, self)

   if self._parent_nursery ~= nil then
      self._parent_nursery._child_nurseries[self] = true
   end

   if self._runner._opts.generate_debug_names and self._parent_nursery ~= nil then
      self._debug_nursery_tree = self._parent_nursery._debug_nursery_tree .. "." .. name
   else
      self._debug_nursery_tree = name
   end

   local deadline
   local fail_on_deadline

   if self._opts.fail_at then
      util.assert(self._opts.move_on_after == nil and self._opts.move_on_at == nil and self._opts.fail_after == nil)
      deadline = self._opts.fail_at
      fail_on_deadline = true
   elseif self._opts.fail_after then
      util.assert(self._opts.move_on_after == nil and self._opts.move_on_at == nil)
      fail_on_deadline = true
      deadline = self._runner:_get_time() + self._opts.fail_after
   elseif self._opts.move_on_at then
      util.assert(self._opts.move_on_after == nil)
      fail_on_deadline = false
      deadline = self._opts.move_on_at
   elseif self._opts.move_on_after then
      fail_on_deadline = false
      deadline = self._runner:_get_time() + self._opts.move_on_after
   else
      deadline = nil
      fail_on_deadline = false
   end

   self._deadline = deadline
   self._should_fail_on_deadline = fail_on_deadline

   if self._deadline == nil then
      util.assert(not fail_on_deadline)
      self._deadline_task = nil
   else
      local deadline_task_name

      if self._runner._opts.generate_debug_names then
         deadline_task_name = string.format("<deadline-%s>", self._debug_nursery_tree)
      else
         deadline_task_name = "<deadline>"
      end

      self._deadline_task = self:start_soon(function()
         self._runner:_await_until_time(self._deadline)
         self:_cancel(true)
      end, { name = deadline_task_name })
   end

   _log("Created new nursery [%s]", self._debug_nursery_tree)
end

function lusc.Nursery:start_soon(task_handler, opts)
   util.assert(not self._is_closed, "Cannot add tasks to closed nursery")
   local task = self._runner:_create_new_task_and_schedule(task_handler, self, nil, opts)
   util.assert(self._child_tasks[task] == nil)
   self._child_tasks[task] = true
   return task
end

function lusc.Nursery:_cancel(from_deadline)
   if self._cancel_requested then
      return
   end

   self._cancel_requested = true
   self._cancel_requested_from_deadline = from_deadline

   if from_deadline then
      _log("Nursery [%s] reached deadline.  Cancelling.", self._debug_nursery_tree)
   else
      _log("Nursery [%s] cancel requested", self._debug_nursery_tree)
   end

   for task, _ in pairs(self._child_tasks) do
      task:_enqueue_pending_error(_CANCELLED)
   end






   self._task:_enqueue_pending_error(_CANCELLED)

   for nursery, _ in pairs(self._child_nurseries) do
      if not nursery._opts.shielded then
         nursery:cancel()
      end
   end
end

function lusc.Nursery:cancel()
   if self._is_closed then
      _log("Attempted to cancel closed nursery [%s]. Ignoring request", self._debug_nursery_tree)
      return
   end

   self:_cancel(false)
end

function lusc.Nursery:close(nursery_err)
   util.assert(not self._is_closed)

   if util.is_log_enabled() then
      if util.map_is_empty(self._child_tasks) then
         _log("Closing nursery [%s] with zero tasks pending", self._debug_nursery_tree)
      else
         local child_tasks_names = {}
         for task, _ in pairs(self._child_tasks) do
            table.insert(child_tasks_names, task._debug_task_tree)
         end
         _log("Closing nursery [%s] with %s tasks pending: %s", self._debug_nursery_tree, #child_tasks_names, table.concat(child_tasks_names, ", "))
      end
   end

   if nursery_err ~= nil then
      self:cancel()
   end





   local all_errors = {}

   if nursery_err ~= nil then
      table.insert(all_errors, nursery_err)
   end

   if self._deadline_task ~= nil and not self._deadline_task._done.is_set then
      self._deadline_task:_enqueue_pending_error(_CANCELLED)
   end


   while not util.map_is_empty(self._child_tasks) do
      for task, _ in pairs(self._child_tasks) do
         util.try({
            action = function() task._done:await() end,
            catch = function(child_err)
               if self._deadline_task == task then


                  util.assert(self._runner:_is_cancelled_error(child_err))
               else
                  _log("Encountered error while waiting for task [%s] to complete while closing nursery [%s]: %s", task._debug_task_tree, self._debug_nursery_tree, child_err)
                  table.insert(all_errors, child_err)
               end
            end,
            finally = function()
               util.assert(task._done.is_set)
               self._child_tasks[task] = nil
            end,
         })
      end
   end

   self._is_closed = true
   util.assert(util.map_is_empty(self._child_nurseries), "[lusc][%s] Found non empty list of child nurseries at end of closing nursery [%s]", self._debug_task_tree, self._debug_nursery_tree)

   if self._parent_nursery ~= nil then
      _log("Removing nursery [%s] from parents child nurseries list", self._debug_nursery_tree)
      self._parent_nursery._child_nurseries[self] = nil
   else
      _log("No parent nursery found for [%s], so no need to remove from child nurseries list", self._debug_nursery_tree)
   end

   local nursery_stack = self._task._child_nursery_stack
   util.assert(nursery_stack[#nursery_stack] == self)
   table.remove(nursery_stack)

   if self._cancel_requested_from_deadline then
      util.assert(self._cancel_requested)
   end

   if self._should_fail_on_deadline and self._cancel_requested_from_deadline then
      table.insert(all_errors, string.format("Nursery [%s] reached given failure deadline", self._debug_nursery_tree))
   end

   if #all_errors > 0 then
      error(lusc.ErrorGroup.new(all_errors), 0)
   end

   return {
      was_cancelled = self._cancel_requested,
      hit_deadline = self._cancel_requested_from_deadline,
   }
end



function lusc._Runner.new(opts)
   util.assert(opts ~= nil, "No options provided to lusc")

   util.assert(opts.time_provider ~= nil, "Missing value for time_provider")
   util.assert(opts.sleep_handler ~= nil, "Missing value for sleep_handler")

   return setmetatable(
   {
      _tasks_by_coro = {},
      _tasks = {},
      _sleep_handler = opts.sleep_handler,
      _opts = opts,
      _pending_error_tasks = {},
      _pending_error_tasks_set = {},
      _main_nursery = nil,
      _requested_quit = false,
   },
   { __index = lusc._Runner })
end

function lusc._Runner:_get_time()
   return self._opts.time_provider()
end

function lusc._Runner:_new_event()
   return lusc.Event.new(self)
end

function lusc._Runner:_find_task_index(task)
   local function comparator(left, right)





      if left._wait_until ~= right._wait_until then
         if left._wait_until > right._wait_until then
            return 1
         end
         return -1
      end

      if left._last_schedule_time ~= right._last_schedule_time then
         if left._last_schedule_time > right._last_schedule_time then
            return 1
         end
         return -1
      end

      if left._id == right._id then
         return 0
      end

      if left._id > right._id then
         return 1
      end

      return -1
   end

   local index = util.binary_search(self._tasks, task, comparator)
   util.assert(index >= 1 and index <= #self._tasks + 1)
   return index
end

function lusc._Runner:_schedule_task(task)
   util.assert(not task._done.is_set)
   util.assert(not task._is_paused)

   local current_time = self:_get_time()

   if util.is_log_enabled() then
      local delta_time = task._wait_until - current_time
      if delta_time < 0 then
         _log("Scheduling task [%s] to run immediately in nursery [%s]", task._debug_task_tree, task._debug_nursery_tree)
      else
         _log("Scheduling task [%s] to run in %.2f seconds in nursery [%s]", task._debug_task_tree, delta_time, task._debug_nursery_tree)
      end
   end

   task._last_schedule_time = current_time
   local index = self:_find_task_index(task)
   util.assert(self._tasks[index] ~= task, "Attempted to schedule task [%s] multiple times", task._debug_task_tree)
   table.insert(self._tasks, index, task)
end

function lusc._Runner:_reschedule(task)
   assert(task._is_paused)
   task._is_paused = false

   task._wait_until = self:_get_time()
   self:_schedule_task(task)
end

function lusc._Runner:_try_get_running_task()
   return self._tasks_by_coro[coroutine.running()]
end

function lusc._Runner:_get_running_task()
   local task = self:_try_get_running_task()
   util.assert(task ~= nil, "[lusc] Unable to find running task")
   return task
end

function lusc._Runner:_checkpoint(result)
   local current_task = self:_get_running_task()

   util.assert(not current_task:_has_pending_errors())

   local current_nursery = current_task:_try_get_current_nursery()

   if current_nursery ~= nil and current_nursery._cancel_requested then
      error(_CANCELLED)
   end

   local pending_error = coroutine.yield(result)
   if pending_error ~= _NO_ERROR then
      _log("Received pending error back from run loop - propagating")


      error(pending_error, 0)
   end
end

function lusc._Runner:_await_task_rescheduled()
   _log("Calling coroutine.yield and passing _TASK_PAUSE")
   self:_checkpoint(_TASK_PAUSE)
end

function lusc._Runner:_await_until_time(until_time)
   _log("Calling coroutine.yield to wait for %.2f seconds", until_time - self:_get_time())
   self:_checkpoint(until_time)
end

function lusc._Runner:_await_sleep(seconds)
   assert(seconds >= 0)
   self:_await_until_time(self:_get_time() + seconds)
end

function lusc._Runner:_await_forever()
   self:_await_until_time(math.huge)
end

function lusc._Runner:_create_new_task_and_schedule(task_handler, nursery_owner, wait_until, opts)
   if wait_until == nil then
      wait_until = self:_get_time()
   end
   local task = lusc.Task.new(self, task_handler, nursery_owner, wait_until, opts)
   task:initialize()
   util.assert(task._coro ~= nil)
   self._tasks_by_coro[task._coro] = task
   self:_schedule_task(task)
   return task
end

function lusc.set_log_handler(log_handler)
   util.set_log_handler(log_handler)
end

function lusc._Runner:_on_task_errored(task, error_obj)

   local traceback = debug.traceback(task._coro)

   _log("Received error from task [%s]: %s\n%s", task._debug_task_tree, error_obj, traceback)

   if task == self._main_task then

      error(lusc.ErrorGroup.new({ error_obj, traceback }), 0)
   else





      local nursery = task._nursery_owner
      util.assert(nursery ~= nil)
      nursery:cancel()

      task._parent_task:_enqueue_pending_error(error_obj)
      task._parent_task:_enqueue_pending_error(traceback)
   end
end

function lusc._Runner:_is_cancelled_error(err)
   if err == _CANCELLED then
      return true
   end

   if util.is_instance(err, lusc.ErrorGroup) then


      local all_errors = (err).errors
      return #all_errors == 1 and all_errors[1] == _CANCELLED
   end

   return false
end

function lusc._Runner:_run_task(task)
   util.assert(not task._is_paused)
   util.assert(not task._done.is_set, "Attempted to run task [%s] but it is already marked as done", task._debug_task_tree)

   local coro_arg



   local pending_errors = task:_pop_pending_errors()

   if #pending_errors > 0 then
      coro_arg = lusc.ErrorGroup.new(pending_errors)
      _log("Resuming task [%s] with %s pending errors", task._debug_task_tree, #pending_errors)
   else
      _log("Resuming task [%s]", task._debug_task_tree)
      coro_arg = _NO_ERROR
   end

   local resume_status, resume_result = coroutine.resume(task._coro, coro_arg)
   local coro_status = coroutine.status(task._coro)

   if resume_status then



   else
      util.assert(coro_status == 'dead')

      if self:_is_cancelled_error(resume_result) then
         _log("Received cancelled error from task [%s]", task._debug_task_tree)
      else
         self:_on_task_errored(task, resume_result)
      end
   end

   if coro_status == 'dead' then
      _log("Detected task [%s] coroutine as dead", task._debug_task_tree)

      if task._nursery_owner ~= nil then
         task._nursery_owner._child_tasks[task] = nil
      end
      self._tasks_by_coro[task._coro] = nil
      task._done:set()
      util.assert(not task._is_paused)




      if self._pending_error_tasks_set[task] then
         self._pending_error_tasks_set[task] = nil
         util.remove_element(self._pending_error_tasks, task)
      end

   elseif resume_result == _TASK_PAUSE then
      _log("Pausing task [%s]", task._debug_task_tree)
      util.assert(not task._is_paused)
      task._is_paused = true
   else
      task._wait_until = resume_result
      self:_schedule_task(task)
   end
end

function lusc._Runner:_create_nursery(opts)
   opts = opts or {}

   local current_task = self:_get_running_task()
   local current_nursery = current_task:_try_get_current_nursery()

   if not opts.shielded and current_nursery ~= nil and current_nursery._cancel_requested then
      error(_CANCELLED)
   end

   local nursery = lusc.Nursery.new(self, current_task, opts)
   nursery:initialize()
   return nursery
end

function lusc._Runner:_open_and_close_nursery(handler, opts)
   local nursery = self:_create_nursery(opts)
   local run_err = nil
   util.try({
      action = function()
         handler(nursery)
      end,
      catch = function(err) run_err = err end,
   })
   return nursery:close(run_err)
end

function lusc._Runner:_remove_task_from_queue(task)
   local index = self:_find_task_index(task)
   util.assert(self._tasks[index] == task)
   table.remove(self._tasks, index)
end

function lusc._Runner:_process_tasks()
   local tasks = self._tasks

   while #tasks > 0 do

      if #self._pending_error_tasks == 0 then
         local wait_delta = tasks[#tasks]._wait_until - self:_get_time()
         if wait_delta > 0 then
            util.assert(self._main_nursery ~= nil)
            self._sleep_handler(wait_delta)
         end
      end


      local current_time = self:_get_time()
      local tasks_to_run = {}


      for _, task in ipairs(self._pending_error_tasks) do
         util.assert(not task._done.is_set)
         util.assert(not task._is_paused)

         table.insert(tasks_to_run, task)
         self:_remove_task_from_queue(task)
      end




      while #tasks > 0 and tasks[#tasks]._wait_until - current_time <= 0 do
         local task = table.remove(tasks)


         if self._pending_error_tasks_set[task] == nil then
            util.assert(not task._done.is_set)
            util.assert(not task._is_paused)
            table.insert(tasks_to_run, task)
         end
      end

      util.clear_table(self._pending_error_tasks)
      util.clear_table(self._pending_error_tasks_set)

      for _, task in ipairs(tasks_to_run) do
         self:_run_task(task)
      end


      while #tasks > 0 and tasks[#tasks]._done.is_set do
         table.remove(tasks)
      end
   end
end

function lusc._Runner:_run(entry_point)
   self._main_task = self:_create_new_task_and_schedule(function()
      self:_open_and_close_nursery(function(nursery)
         util.assert(self._main_nursery == nil)
         self._main_nursery = nursery
         nursery:start_soon(util.partial_func1(entry_point, nursery))
      end)
   end)

   self:_process_tasks()

   util.assert(#self._pending_error_tasks == 0)
   util.assert(util.map_is_empty(self._pending_error_tasks_set))
   util.assert(util.map_is_empty(self._tasks_by_coro))
   util.assert(#self._tasks == 0)
   util.assert(self._main_task._done.is_set)
   self._main_task = nil
   self._main_nursery = nil
end



function lusc._get_runner()
   local result = lusc._current_runner
   util.assert(result ~= nil, "[lusc] Current operation is not being executed underneath lusc.run")
   return result
end

function lusc.open_nursery(handler, opts)
   return lusc._get_runner():_open_and_close_nursery(handler, opts)
end


function lusc.get_time()
   return lusc._get_runner():_get_time()
end

function lusc.await_sleep(seconds)
   lusc._get_runner():_await_sleep(seconds)
end

function lusc.await_until_time(until_time)
   lusc._get_runner():_await_until_time(until_time)
end

function lusc.await_forever()
   lusc.await_until_time(math.huge)
end

function lusc.new_event()
   return lusc._get_runner():_new_event()
end

function lusc.run(opts)
   util.assert(opts ~= nil, "No options provided to lusc")
   util.assert(opts.time_provider ~= nil, "Missing value for time_provider")
   util.assert(opts.entry_point ~= nil, "Missing value for entry_point")

   util.assert(lusc._current_runner == nil)
   lusc._current_runner = lusc._Runner.new(opts)
   util.try({
      action = function()
         lusc._current_runner:_run(opts.entry_point)
      end,
      finally = function()
         lusc._current_runner = nil
      end,
   })
end

return lusc
