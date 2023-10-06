
-- Design notes:
-- We basically just copy the design of trio with a few minor differences (no cancel scopes and instead we just use more nurseries)
-- https://trio.readthedocs.io/en/stable/reference-core.html#general-principles
-- This means:
-- * All operations either produce a checkpoint or they do not.  They do not sometimes yield depending on runtime state.  This is important because users sometimes have to reason about when yields occur.  One exception to this rule is when errors occur.  In this case the operation may immediately raise the error without a yield

-- Also this started based on the code from this great series here:
-- https://gist.github.com/belm0/4c6d11f47ccd31a231cde04616d6bb22

local util <const> = require("lusc.util")

local task_counter = 0
local nursery_counter = 0

local _TASK_PAUSE = setmetatable({}, {__tostring=function():string return '<task_pause>' end})
local _NO_ERROR = setmetatable({}, {__tostring=function():string return '<no_error>' end})
local _CANCELLED = setmetatable({}, {__tostring=function():string return '<cancelled>' end})

local record lusc
   record Opts
      -- Default: false
      generate_debug_names:boolean

      -- should returns fractional time in seconds from an arbitrary reference point
      time_provider:function():number
      sleep_handler:function(seconds:number)
      entry_point:function(Nursery)
   end

   record ErrorGroup
      errors:{any}
   end

   record Task
      record Opts
         name:string
      end

      _id: integer
      _is_paused: boolean
      _last_schedule_time: number
      _coro: thread
      _nursery_owner: Nursery
      _parent_task: Task
      _wait_until:number
      _done:Event
      _pending_errors:{any}
      _opts:Opts
      _runner:_Runner
      _child_nursery_stack:{Nursery}
      -- Note: requires generate_debug_names to be set
      _debug_task_tree:string
      _debug_nursery_tree:string

      -- Consider exposing these to users
      -- name: string
      -- coro: thread
      -- parent_nursery: Nursery
      -- child_nurseries: {Nursery}

      _try_get_current_nursery:function(self: Task):Nursery
   end

   record Event
      is_set:boolean
      _waiting_tasks:{Task}
      _runner:_Runner

      set:function(Event)
      await:function(Event)
   end

   record Nursery
      record Opts
         name:string

         shielded: boolean

         -- note: can only set one of these
         move_on_after:number
         move_on_at:number
         fail_after:number
         fail_at:number
      end

      record Result
         was_cancelled: boolean
         hit_deadline: boolean
      end

      _id: integer
      _deadline: number
      _is_closed: boolean
      _should_fail_on_deadline: boolean
      _debug_task_tree:string
      _debug_nursery_tree:string
      _opts:Opts
      _deadline_task:Task
      _runner:_Runner
      _task:Task
      _child_tasks: {Task:boolean}
      _parent_nursery: Nursery
      _child_nurseries: {Nursery:boolean}
      _cancel_requested: boolean
      _cancel_requested_from_deadline: boolean

      _cancel:function(self: Nursery, from_deadline:boolean)
      cancel:function(self: Nursery)

      start_soon:function(self: Nursery, func:function(), lusc.Task.Opts):Task
   end

   record _Runner
      _tasks_by_coro: {thread:Task}

      -- list sorted by wait_until, nearest time last
      _tasks: {Task}

      _sleep_handler:function(number)
      _pending_error_tasks: {Task}
      _pending_error_tasks_set: {Task:boolean}
      _main_nursery: Nursery
      _main_task: Task
      _opts: Opts
      _requested_quit:boolean

      _get_running_task:function(_Runner):Task
      _try_get_running_task:function(_Runner):Task
      _create_new_task_and_schedule:function(_Runner, func:function(), lusc.Nursery, wait_until:number, opts:Task.Opts):Task
      _remove_task_from_queue:function(_Runner, task:lusc.Task)

      _await_until_time:function(_Runner, until_time:number)
      _await_task_rescheduled:function(_Runner)
      _reschedule:function(_Runner, task:Task)
      _is_cancelled_error:function(_Runner, err:any):boolean

      _get_time:function(_Runner):number
   end

   _current_runner:lusc._Runner
end

-- *********** util ***********

local function _log(format:string, ...:any)
   if not util.is_log_enabled() then
      return
   end

   local current_task = lusc._current_runner:_try_get_running_task()
   local message:string

   if current_task == nil then
      message = string.format(format, ...)
   else
      message = string.format("[%s] " .. format, current_task._debug_task_tree, ...)
   end

   util.log(message)
end

-- *********** ErrorGroup ***********

function lusc.ErrorGroup.new(errors:{any}):lusc.ErrorGroup
   local adjusted_errors:{any} = {}

   local has_added_cancel = false

   -- No point in adding multiple cancel errors I think?
   local function add_error(err:any)
      if err == _CANCELLED then
         if not has_added_cancel then
            has_added_cancel = true
            table.insert(adjusted_errors, err)
         end
      else
         table.insert(adjusted_errors, err)
      end
   end

   -- TODO - we might want to automatically discard duplicates here
   -- which can happen since the same error can be propagated to multiple
   -- receivers
   for _, err in ipairs(errors) do
      if util.is_instance(err, lusc.ErrorGroup) then
         for _, sub_error in ipairs((err as lusc.ErrorGroup).errors) do
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
      } as lusc.ErrorGroup,
      { __index = lusc.ErrorGroup } as metatable<lusc.ErrorGroup>)
end

function lusc.ErrorGroup:__tostring():string
   local lines = {}
   for _, err in ipairs(self.errors) do
      table.insert(lines, tostring(err))
   end
   return table.concat(lines, '\n')
end

-- *********** Event ***********

function lusc.Event.new(runner:lusc._Runner):lusc.Event
   return setmetatable(
      {
         _runner = runner,
         is_set = false,
         _waiting_tasks = {},
      } as lusc.Event,
      { __index = lusc.Event } as metatable<lusc.Event>)
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

-- *********** Task ***********

function lusc.Task.new(runner:lusc._Runner, task_handler:function(), nursery_owner:lusc.Nursery, wait_until:number, opts:lusc.Task.Opts):lusc.Task
   util.assert(wait_until ~= nil)
   util.assert(runner ~= nil)
   util.assert(task_handler ~= nil)

   task_counter = task_counter + 1

   local parent_task:lusc.Task
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
         _nursery_owner = nursery_owner, -- null for root task
         _debug_task_tree = nil,
         _child_nursery_stack = {},
         _wait_until = wait_until,
         _pending_errors = {},
         _debug_nursery_tree = nil,
      } as lusc.Task,
      { __index = lusc.Task } as metatable<lusc.Task>)
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

function lusc.Task:_try_get_current_nursery():lusc.Nursery
   local stack = self._child_nursery_stack

   if #stack == 0 then
      -- null for root task
      if self._nursery_owner == nil then
         return nil
      end

      return self._nursery_owner
   end

   return stack[#stack]
end

function lusc.Task:_pop_pending_errors():{any}
   local result = self._pending_errors
   self._pending_errors = {}
   return result
end

function lusc.Task:_enqueue_pending_error(err:any)
   table.insert(self._pending_errors, err)

   -- Jump to start of next run loop
   if not self._is_paused and not self._runner._pending_error_tasks_set[self] then
      -- We store both a map and a list because we want to preserve the order that
      -- errors occurred in (older errors run first)
      -- But also want O(1) lookup
      table.insert(self._runner._pending_error_tasks, self)
      self._runner._pending_error_tasks_set[self] = true
   end
end

function lusc.Task:_has_pending_errors():boolean
   return #self._pending_errors > 0
end

-- *********** Nursery ***********

function lusc.Nursery.new(runner:lusc._Runner, task:lusc.Task, opts:lusc.Nursery.Opts):lusc.Nursery
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
      } as lusc.Nursery,
      { __index = lusc.Nursery } as metatable<lusc.Nursery>)
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

   local deadline:number
   local fail_on_deadline:boolean

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
      local deadline_task_name:string

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

function lusc.Nursery:start_soon(task_handler:function(), opts:lusc.Task.Opts):lusc.Task
   util.assert(not self._is_closed, "Cannot add tasks to closed nursery")
   local task = self._runner:_create_new_task_and_schedule(task_handler, self, nil, opts)
   util.assert(self._child_tasks[task] == nil)
   self._child_tasks[task] = true
   return task
end

function lusc.Nursery:_cancel(from_deadline:boolean)
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

   -- If nursery is already in the process of closing, and this
   -- is called by one of the sub-tasks, then it's not really
   -- necessary since the nursery will receive the task cancel error
   -- but in cases where the nursery is waiting for an async operation
   -- executed directly in the handler method, it is necessary
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

function lusc.Nursery:close(nursery_err:any):lusc.Nursery.Result
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

   -- Block until all child tasks done
   -- Defer any exceptions until after all children are done
   -- Note that the runner will call cancel() for us here when
   -- one of these tasks fail
   local all_errors = {}

   if nursery_err ~= nil then
      table.insert(all_errors, nursery_err)
   end

   if self._deadline_task ~= nil and not self._deadline_task._done.is_set then
      self._deadline_task:_enqueue_pending_error(_CANCELLED)
   end

   -- Note here that more child tasks can be added while we are iterating over the list
   while not util.map_is_empty(self._child_tasks) do
      for task, _ in pairs(self._child_tasks) do
         util.try {
            action = function():nil task._done:await() end,
            catch = function(child_err:any):nil
               if self._deadline_task == task then
                  -- Don't propagate in this case
                  -- Timeout failure is added as an error below instead
                  util.assert(self._runner:_is_cancelled_error(child_err))
               else
                  _log("Encountered error while waiting for task [%s] to complete while closing nursery [%s]: %s", task._debug_task_tree, self._debug_nursery_tree, child_err)
                  table.insert(all_errors, child_err)
               end
            end,
            finally = function():nil
               util.assert(task._done.is_set)
               self._child_tasks[task] = nil
            end,
         }
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

-- *********** _Runner ***********

function lusc._Runner.new(opts:lusc.Opts):lusc._Runner
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
      } as lusc._Runner,
      { __index = lusc._Runner } as metatable<lusc._Runner>)
end

function lusc._Runner:_get_time():number
   return self._opts.time_provider()
end

function lusc._Runner:_new_event():lusc.Event
   return lusc.Event.new(self)
end

function lusc._Runner:_find_task_index(task:lusc.Task):integer
   local function comparator(left:lusc.Task, right:lusc.Task):integer
      -- Sort first by the next run time (in decreasing order so that we can pop done tasks off the end)
      -- then by schedule time, then by ID
      -- This way, for tasks that have the same run time, we execute in the order they were scheduled
      -- And by ID so that every task has one unique index, so we can do a get() easily

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

function lusc._Runner:_schedule_task(task:lusc.Task)
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

function lusc._Runner:_reschedule(task:lusc.Task)
   assert(task._is_paused)
   task._is_paused = false

   task._wait_until = self:_get_time()
   self:_schedule_task(task)
end

function lusc._Runner:_try_get_running_task():lusc.Task
   return self._tasks_by_coro[coroutine.running()]
end

function lusc._Runner:_get_running_task():lusc.Task
   local task = self:_try_get_running_task()
   util.assert(task ~= nil, "[lusc] Unable to find running task")
   return task
end

function lusc._Runner:_checkpoint(result:any)
   local current_task = self:_get_running_task()
   -- Is this possible?
   util.assert(not current_task:_has_pending_errors())

   local current_nursery = current_task:_try_get_current_nursery()

   if current_nursery ~= nil and current_nursery._cancel_requested then
      error(_CANCELLED)
   end

   local pending_error = coroutine.yield(result)
   if pending_error ~= _NO_ERROR then
      _log("Received pending error back from run loop - propagating")
      -- NOTE: Disable prepending location to error strings, since
      --   that already happened when the original error was raised.
      error(pending_error, 0)
   end
end

function lusc._Runner:_await_task_rescheduled()
   _log("Calling coroutine.yield and passing _TASK_PAUSE")
   self:_checkpoint(_TASK_PAUSE)
end

function lusc._Runner:_await_until_time(until_time:number)
   _log("Calling coroutine.yield to wait for %.2f seconds", until_time - self:_get_time())
   self:_checkpoint(until_time)
end

function lusc._Runner:_await_sleep(seconds:number)
   assert(seconds >= 0)
   self:_await_until_time(self:_get_time() + seconds)
end

function lusc._Runner:_await_forever()
   self:_await_until_time(math.huge)
end

function lusc._Runner:_create_new_task_and_schedule(task_handler:function(), nursery_owner:lusc.Nursery, wait_until:number, opts:lusc.Task.Opts):lusc.Task
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

function lusc.set_log_handler(log_handler:function(string))
   util.set_log_handler(log_handler)
end

function lusc._Runner:_on_task_errored(task:lusc.Task, error_obj:any)
   -- Must grab the traceback before unwinding stack for some reason
   local traceback = debug.traceback(task._coro)

   _log("Received error from task [%s]: %s\n%s", task._debug_task_tree, error_obj, traceback)

   if task == self._main_task then
      -- raise unhandled error to caller of event loop
      error(lusc.ErrorGroup.new({error_obj, traceback}), 0)
   else
      -- Note here that we are cancelling the nursery owner
      -- and not just the current nursery (which might be a child of nursery owner)
      -- The current nursery should be cancelled due to this, since the owning nursery
      -- should propagate the cancel downwards, and the parent task
      -- should propagate the error upwards
      local nursery = task._nursery_owner
      util.assert(nursery ~= nil)
      nursery:cancel()

      task._parent_task:_enqueue_pending_error(error_obj)
      task._parent_task:_enqueue_pending_error(traceback)
   end
end

function lusc._Runner:_is_cancelled_error(err:any):boolean
   if err == _CANCELLED then
      return true
   end

   if util.is_instance(err, lusc.ErrorGroup) then
      -- Note that the logic in ErrorGroup should guarantee that we don't 
      -- get duplicate instances of cancelled here
      local all_errors = (err as lusc.ErrorGroup).errors
      return #all_errors == 1 and all_errors[1] == _CANCELLED
   end

   return false
end

function lusc._Runner:_run_task(task:lusc.Task)
   util.assert(not task._is_paused)
   util.assert(not task._done.is_set, "Attempted to run task [%s] but it is already marked as done", task._debug_task_tree)

   local coro_arg:any

   -- Important to clear errors here since sometimes we keep executing the same task multiple
   -- times even after one error occurs (eg. nursery close method)
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
      -- Tempting to do this, where should_forward_error is true if we passed a pending error, 
      -- but sometimes the task will handle the exception (eg. nursery close), so not possible
      -- util.assert(not should_forward_error, "Expected task [%s] to forward error but task coroutine completed successfully instead", task._debug_task_tree)
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

      -- If the task calls cancel on the nursery it is in, and then completes without a yield,
      -- then it can get added to _pending_error_tasks_set, so we need
      -- to remove it there
      if self._pending_error_tasks_set[task] then
         self._pending_error_tasks_set[task] = nil
         util.remove_element(self._pending_error_tasks, task)
      end

   elseif resume_result == _TASK_PAUSE then
      _log("Pausing task [%s]", task._debug_task_tree)
      util.assert(not task._is_paused)
      task._is_paused = true
   else
      task._wait_until = resume_result as number
      self:_schedule_task(task)
   end
end

function lusc._Runner:_create_nursery(opts:lusc.Nursery.Opts):lusc.Nursery
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

function lusc._Runner:_open_and_close_nursery(handler:function(lusc.Nursery), opts:lusc.Nursery.Opts):lusc.Nursery.Result
   local nursery = self:_create_nursery(opts)
   local run_err:any = nil
   util.try {
      action = function():nil
         handler(nursery)
      end,
      catch = function(err:string):nil run_err = err end,
   }
   return nursery:close(run_err)
end

function lusc._Runner:_remove_task_from_queue(task:lusc.Task)
   local index = self:_find_task_index(task)
   util.assert(self._tasks[index] == task)
   table.remove(self._tasks, index)
end

function lusc._Runner:_process_tasks()
   local tasks = self._tasks

   while #tasks > 0 do
      -- sleep until next event, unless there are tasks with pending errors
      if #self._pending_error_tasks == 0 then
         local wait_delta = tasks[#tasks]._wait_until - self:_get_time()
         if wait_delta > 0 then
            util.assert(self._main_nursery ~= nil)
            self._sleep_handler(wait_delta)
         end
      end

      -- collect batch of tasks which are ready to run or have pending error
      local current_time = self:_get_time()
      local tasks_to_run = {}

      -- Add pending errors first so they run first
      for _, task in ipairs(self._pending_error_tasks) do
         util.assert(not task._done.is_set)
         util.assert(not task._is_paused)

         table.insert(tasks_to_run, task)
         self:_remove_task_from_queue(task)
      end

      -- Tasks that have the same wait_until time will be ordered by their
      -- id, which is not ideal, but should be rare since in most cases
      -- tasks should have a unique wait_until value
      while #tasks > 0 and tasks[#tasks]._wait_until - current_time <= 0 do
         local task = table.remove(tasks)

         -- skip pending error tasks since they were already added
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

      -- remove completed tasks
      while #tasks > 0 and tasks[#tasks]._done.is_set do
         table.remove(tasks)
      end
   end
end

function lusc._Runner:_run(entry_point:function(lusc.Nursery):nil)
   self._main_task = self:_create_new_task_and_schedule(function()
      self:_open_and_close_nursery(function(nursery:lusc.Nursery)
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

-- *********** lusc ***********

function lusc._get_runner():lusc._Runner
   local result = lusc._current_runner
   util.assert(result ~= nil, "[lusc] Current operation is not being executed underneath lusc.run")
   return result
end

function lusc.open_nursery(handler:function(nursery:lusc.Nursery), opts:lusc.Nursery.Opts):lusc.Nursery.Result
   return lusc._get_runner():_open_and_close_nursery(handler, opts)
end

-- returns fractional time in seconds from an arbitrary reference point
function lusc.get_time():number
   return lusc._get_runner():_get_time()
end

function lusc.await_sleep(seconds:number)
   lusc._get_runner():_await_sleep(seconds)
end

function lusc.await_until_time(until_time:number)
   lusc._get_runner():_await_until_time(until_time)
end

function lusc.await_forever()
   lusc.await_until_time(math.huge)
end

function lusc.new_event():lusc.Event
   return lusc._get_runner():_new_event()
end

function lusc.run(opts:lusc.Opts)
   util.assert(opts ~= nil, "No options provided to lusc")
   util.assert(opts.time_provider ~= nil, "Missing value for time_provider")
   util.assert(opts.entry_point ~= nil, "Missing value for entry_point")

   util.assert(lusc._current_runner == nil)
   lusc._current_runner = lusc._Runner.new(opts)
   util.try {
      action = function():nil
         lusc._current_runner:_run(opts.entry_point as function():nil)
      end,
      finally = function():nil
         lusc._current_runner = nil
      end
   }
end

return lusc

