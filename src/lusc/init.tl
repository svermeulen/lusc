
-- Design notes:
-- We basically just copy the design of trio with a few minor differences (no cancel scopes and instead we just use more nurseries)
-- https://trio.readthedocs.io/en/stable/reference-core.html#general-principles
-- This means:
-- * All operations either produce a checkpoint or they do not.  They do not sometimes yield depending on runtime state.  This is important because users sometimes have to reason about when yields occur.  One exception to this rule is when errors occur.  In this case the operation may immediately raise the error without a yield

-- Also this started based on the code from this great series here:
-- https://gist.github.com/belm0/4c6d11f47ccd31a231cde04616d6bb22

local uv <const> = require("luv")
local milliseconds_per_second = 1000.0
local util <const> = require("lusc.internal.util")
local Queue <const> = require("lusc.internal.queue")

local task_counter = 0
local nursery_counter = 0
local cancel_scope_counter = 0

local function _get_time():number
   return uv.hrtime() / 1e9
end

local function _sleep(seconds:number)
   uv.sleep(math.floor(seconds * milliseconds_per_second))
end

local _TASK_PAUSE = setmetatable({}, {__tostring=function():string return '<task_pause>' end})
local _NO_ERROR = setmetatable({}, {__tostring=function():string return '<no_error>' end})

local record ChannelImpl<T>
   _runner:lusc._Runner
   _waiting_receive_tasks:Queue<lusc.Task>
   _waiting_send_tasks:Queue<lusc.Task>
   _buffer:Queue<T>
   _is_closed:boolean
   _max_buffer_size:integer

   await_send:function(ChannelImpl<T>, value:T)
   send:function(ChannelImpl<T>, value:T)

   await_receive_next:function(ChannelImpl<T>):T, boolean
   await_receive_all:function(ChannelImpl<T>):function():T

   receive_next:function(ChannelImpl<T>):T, boolean

   close:function(ChannelImpl<T>)
   close_after:function(ChannelImpl<T>, function())
end

local record lusc
   record Scheduler
      schedule:function(Scheduler, delay_seconds:number, callback:function())
      dispose:function(Scheduler)
   end

   record DefaultScheduler
      _step_timer:uv.Timer

      schedule:function(DefaultScheduler, delay_seconds:number, callback:function())
      dispose:function(DefaultScheduler)

      new:function():DefaultScheduler
   end

   record Channel<T>
      --- Only needed when there is a buffer max size
      -- @return true if the receiving side is closed, in which
      -- case there is no need to send any more values
      await_send:function(Channel<T>, value:T)

      --- raises an error if the buffer is full
      -- @return true if the receiving side is closed, in which
      -- case there is no need to send any more values
      send:function(Channel<T>, value:T)

      --- @return true if both the sending side is closed and there are no more
      -- @return received value
      -- values to receive
      await_receive_next:function(Channel<T>):T, boolean

      --- Receives all values, until sender is closed
      await_receive_all:function(Channel<T>):function():T

      --- raises an error if nothing is there to receive
      -- @return received value
      -- @return true if both the sending side is closed and there are no more
      -- values to receive
      receive_next:function(Channel<T>):T, boolean

      --- Indicates that the sender has completed and receiver can end
      close:function(Channel<T>)

      -- Just calls close() after the given function completes
      close_after:function(Channel<T>, function())
   end

   record Opts
      -- Default: false
      generate_debug_names:boolean

      -- err is nil when completed successfully
      on_completed: function(err:ErrorGroup)

      -- Optional - by default it uses luv timer
      scheduler_factory: function():Scheduler
   end

   record ErrorGroup
      errors:{any}
      new:function({any}):ErrorGroup
   end

   record Task
      record Opts
         name:string
      end

      _id: integer
      _last_schedule_time: number
      _coro: thread
      _nursery_owner: Nursery
      _parent_task: Task
      _wait_until:number
      _done:Event
      _is_scheduled:boolean
      _min_shield_depth:integer
      _is_discarded:boolean
      _pending_errors:{any}
      _pending_cancellation_errors:{CancelledError:boolean}
      _opts:Opts
      _runner:_Runner
      _child_nursery_stack:{Nursery}
      _cancel_scope_stack:{CancelScope}
      -- Note: requires generate_debug_names to be set
      _debug_task_tree:string
      _debug_nursery_tree:string
      _wake_for_pending_errors:boolean

      parent: Task

      -- Consider exposing these to users
      -- name: string
      -- coro: thread
      -- parent_nursery: Nursery
      -- child_nurseries: {Nursery}

      _try_get_current_nursery:function(self: Task):Nursery
   end

   record Event
      is_set:boolean
      _waiting_tasks:Queue<Task>
      _runner:_Runner

      set:function(Event)
      await:function(Event)
   end

   record CancelledError
      _trigger_scope: CancelScope
   end

   record DeadlineOpts
      -- note: can only set one of these
      move_on_after:number
      move_on_at:number
      fail_after:number
      fail_at:number
   end

   record CancelScope
      record Opts
         shielded: boolean
         name:string

         -- note: can only set one of these
         move_on_after:number
         move_on_at:number
         fail_after:number
         fail_at:number
      end

      record ShortcutOpts
         shielded: boolean
         name:string
      end

      record Result
         was_cancelled: boolean
         hit_deadline: boolean
      end

      cancel:function(CancelScope)

      _old_pending_errors:{lusc.CancelledError}
      _depth:integer
      _default_deadline_opts:DeadlineOpts
      _id:integer
      _debug_name:string
      _has_cancelled:boolean
      _cancel_error:CancelledError
      _children:{CancelScope}
      _deadline_task:Task
      _hit_deadline:boolean
      _cancel_observers:{function(CancelledError)}
      _runner:_Runner
      _shielded:boolean
      _fail_on_deadline:boolean
      _task:Task
      _is_running:boolean
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

      _id: integer
      _is_closed: boolean
      _debug_task_tree:string
      _debug_nursery_tree:string
      _name: string
      _runner:_Runner
      _task:Task
      _child_tasks: {Task:boolean}
      _parent_nursery: Nursery
      _child_nurseries: {Nursery:boolean}

      cancel_scope: CancelScope

      -- TODO
      -- start:function()

      start_soon:function(self: Nursery, func:function(), Task.Opts)
   end

   record _Runner
      _tasks_by_coro: {thread:Task}
      _task_queue: {Task} -- list sorted by wait_until, nearest time last
      _has_started: boolean
      _has_stopped: boolean
      _main_nursery: Nursery
      _main_task: Task
      _opts: Opts
      _is_within_task_loop:boolean
      _stop_requested_event:Event
      _root_error:ErrorGroup
      _initial_handlers:{{function(), Task.Opts}}
      _next_step_time:number
      _scheduler: Scheduler
      _main_nursery_deadline_opts:DeadlineOpts

      _get_running_task:function(_Runner):Task
      _try_get_running_task:function(_Runner):Task
      _create_new_task_and_schedule:function(_Runner, func:function(), Nursery, wait_until:number, opts:Task.Opts):Task
      _unschedule_task:function(_Runner, task:Task)
      _await_until:function(_Runner, until_time:number)
      _await_sleep:function(_Runner, seconds:number)
      _await_task_rescheduled:function(_Runner)
      _schedule_now:function(_Runner, task:Task)
      _is_cancelled_error:function(_Runner, err:any):boolean
      _step:function(_Runner)
      _stop_requested:function(_Runner):boolean
      _discard_task:function(_Runner, task:Task)
   end

   _current_runner:_Runner

   open_nursery:function(handler:function(nursery:Nursery), opts:Nursery.Opts):CancelScope.Result
   get_time:function():number
   await_sleep:function(seconds:number)
   await_until:function(until_time:number)
   await_forever:function()
   new_event:function():Event
   start:function(opts:Opts)

   -- Note that this will only cancel tasks if one of the move_on* or fail_* options
   -- are provided.  Otherwise it will wait forever for tasks to complete gracefully
   -- Note also that if block_until_stopped is provided, it will block 
   stop:function(opts:DeadlineOpts)

   -- Long running tasks can check this periodically, and then shut down
   -- gracefully, instead of relying on cancels
   stop_requested:function():boolean

   -- If true, then the current code is being executed
   -- under the lusc task loop and therefore lusc await
   -- methods can be used
   is_processing:function():boolean

   move_on_after:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result
   move_on_at:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result
   fail_after:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result
   fail_at:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result

   cancel_scope:function(handler:function(scope:CancelScope), opts:CancelScope.Opts):CancelScope.Result

   --- @return true if the given object is an instance of ErrorGroup
   -- and also that it only consists of the cancelled error
   is_cancelled_error:function(err:any):boolean

   schedule:function(handler:function(), opts:Task.Opts)

   -- schedule_wrap: function(function(), opts:Task.Opts): function()
   -- schedule_wrap: function<T>(function(T), opts:Task.Opts): function(T)
   -- schedule_wrap: function<T1,T2>(function(T1, T2), opts:Task.Opts): function(T1, T2)

   has_started:function():boolean

   get_root_nursery:function():Nursery

   cancel_all:function()
   open_channel:function<T>(max_buffer_size:integer):Channel<T>

   get_running_task:function():Task
   try_get_running_task:function():Task

   schedule_wrap:function(handler:function(...:any), opts:Task.Opts):function(...:any)
end

-- *********** util ***********

local function _remove_element<T>(list:{T}, item:T)
   local index = util.index_of(list, item)
   util.assert(index ~= -1, "Attempted to remove item from array that does not exist in array")
   table.remove(list, index)
end

local function _is_instance(obj:any, cls:any):boolean
   -- We use a simple class model by convention where class is __index
   return getmetatable(obj).__index == cls
end

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

   util.log("[lusc] " .. message)
end

local function _binary_search<T>(items:{T}, item:T, comparator:function(T, T):integer):integer
   local low = 1
   local high = #items

   while low <= high do
      local mid = math.floor((low + high) / 2)
      local candidate = items[mid]
      local cmp = comparator(candidate, item)

      if cmp == 0 then
         return mid
      elseif cmp > 0 then
         low = mid + 1
      else
         high = mid - 1
      end
   end
   return low
end

-- *********** DefaultScheduler ***********

function lusc.DefaultScheduler.new():lusc.DefaultScheduler
   return setmetatable(
      {
         _step_timer = uv.new_timer(),
      } as lusc.DefaultScheduler,
      { __index = lusc.DefaultScheduler } as metatable<lusc.DefaultScheduler>)
end

function lusc.DefaultScheduler:schedule(min_time:number, callback:function())
   local function restart_timer()
      self._step_timer:stop()
      local delay = math.max(0, min_time - _get_time())
      -- We need to guarantee that we don't call the callback before the given minimum time
      -- luve does not offer the same guarantee though, so need to 
      -- We add 3ms just to avoid this from happening constantly, and happen semi-regularly instead,
      -- and also to avoid issues with loss of precision, since according to luv docs, it takes an 
      -- integer number of milliseconds
      assert(self._step_timer:start(math.floor(delay * milliseconds_per_second) + 3, 0, function()
         local new_time = _get_time()
         if new_time < min_time then
            restart_timer()
         else
            callback()
         end
      end))
   end
   restart_timer()
end

function lusc.DefaultScheduler:dispose()
   self._step_timer:close()
end

-- *********** ChannelImpl ***********

function ChannelImpl.new<T>(runner:lusc._Runner, max_buffer_size:integer):ChannelImpl<T>
   util.assert(max_buffer_size == nil or max_buffer_size > 0, "max_buffer_size must be nil or > 0")

   return setmetatable(
      {
         _runner = runner,
         _max_buffer_size = max_buffer_size,
         _is_closed = false,
         _waiting_receive_tasks = Queue(),
         _waiting_send_tasks = Queue(),
         _buffer = Queue(),
      } as ChannelImpl<T>,
      { __index = ChannelImpl } as metatable<ChannelImpl>)
end

function ChannelImpl:await_send(value:T)
   util.assert(not self._is_closed, "[lusc] Attempted to send on a closed send channel")

   if self._max_buffer_size == nil then
      -- Follow the trio rule of always awaiting given await_ prefix
      -- even when it isn't necessary
      self._runner:_await_sleep(0)
      self:send(value)
      return
   end

   local has_awaited = false

   local function can_send():boolean
      return self._buffer.count < self._max_buffer_size
   end

   local task = self._runner:_get_running_task()

   while true do
      util.assert(not self._is_closed, "[lusc] Attempted to send on a closed send channel")

      if not can_send() then
         self._waiting_send_tasks:enqueue(task)

         util.try {
            action = function():nil
               self._runner:_await_task_rescheduled()
            end,
            catch = function(err:any):nil
               -- Note that this may or may not remove a value,
               -- since it could have been rescheduled normally on the receive side,
               -- and then subsequently received a pending error
               self._waiting_send_tasks:remove_value(task)
               error(err)
            end
         }
         util.assert(not self._waiting_send_tasks:contains(task))

         has_awaited = true
      end

      if can_send() then
         -- Follow the trio rule of always awaiting given await_ prefix
         -- even when it isn't necessary
         if has_awaited then
            self:send(value)
            return
         end

         self._runner:_await_sleep(0)
         has_awaited = true
      end
   end
end

function ChannelImpl:send(value:T)
   util.assert(not self._is_closed, "[lusc] Attempted to send on a closed send channel")

   if self._max_buffer_size ~= nil and self._buffer.count >= self._max_buffer_size then
      error("Buffer is full - cannot perform synchronous send. Use await_send instead.")
   end

   self._buffer:enqueue(value)
   _log("Added new value to channel buffer - waking up %s waiting tasks", self._waiting_receive_tasks.count)

   -- Wake up all waiting tasks that aren't already awake
   -- We could just wake up the first task, but it's safer to wake up all,
   -- in case that first task errors and does not eat the new value (eg. due to pending error)
   -- If they can't eat any values they'll just be added back to _waiting_receive_tasks
   while not self._waiting_receive_tasks:empty() do
      self._runner:_schedule_now(self._waiting_receive_tasks:dequeue())
   end
end

function ChannelImpl:close()
   util.assert(not self._is_closed, "Attempted to close channel twice")
   self._is_closed = true

   -- Wake up all waiting tasks that aren't already awake
   while not self._waiting_receive_tasks:empty() do
      self._runner:_schedule_now(self._waiting_receive_tasks:dequeue())
   end
end

function ChannelImpl:close_after(func:function())
   util.try {
      action = func as (function():nil),
      finally = function():nil
         self:close()
      end
   }
end

function ChannelImpl:await_receive_next():T, boolean
   local has_awaited = false
   local task = self._runner:_get_running_task()

   while true do
      if self._buffer:empty() then
         if self._is_closed then
            return nil, true
         end

         _log("Channel buffer is empty - awaiting for new value")
         self._waiting_receive_tasks:enqueue(task)

         util.try {
            action = function():nil
               self._runner:_await_task_rescheduled()
            end,
            catch = function(err:any):nil
               -- Note that this may or may not remove a value,
               -- since it could have been rescheduled normally on the send side,
               -- and then subsequently received a pending error
               self._waiting_receive_tasks:remove_value(task)
               error(err)
            end
         }
         util.assert(not self._waiting_receive_tasks:contains(task))

         has_awaited = true

         if self._buffer:empty() and self._is_closed then
            return nil, true
         end
      end

      if not self._buffer:empty() then
         -- Follow the trio rule of always awaiting given await_ prefix
         -- even when it isn't necessary
         if has_awaited then
            return self:receive_next()
         end

         self._runner:_await_sleep(0)
         has_awaited = true
      end
   end
end

function ChannelImpl:await_receive_all():function():T
   return function():T
      local value, is_done = self:await_receive_next()
      if is_done then
         return nil
      end

      return value
   end
end

function ChannelImpl:receive_next():T, boolean
   if self._buffer:empty() then
      if self._is_closed then
         return nil, true
      end

      error("Attempted to synchronous receive on an empty lusc channel")
   end

   local val = self._buffer:dequeue()

   -- Wake up all tasks waiting to add more data to buffer
   -- We could just wake up the first task, but it's safer to wake up all,
   -- since there are various ways it could fail to fill in a new value that
   -- other waiting tasks could have (eg. pending errors)
   while not self._waiting_send_tasks:empty() do
      self._runner:_schedule_now(self._waiting_send_tasks:dequeue())
   end

   return val, false
end

-- *********** ErrorGroup ***********

function lusc.ErrorGroup.new(errors:{any}):lusc.ErrorGroup
   local adjusted_errors:{any} = {}
   local seen_map = {}

   -- Duplicates are sometimes added, so remove these
   local function add_error(err:any)
      if seen_map[err] == nil then
         seen_map[err] = true
         table.insert(adjusted_errors, err)
      end
   end

   for _, err in ipairs(errors) do
      if _is_instance(err, lusc.ErrorGroup) then
         for _, sub_error in ipairs((err as lusc.ErrorGroup).errors) do
            util.assert(not _is_instance(sub_error, lusc.ErrorGroup))
            add_error(sub_error)
         end
      else
         add_error(err)
      end
   end

   local this = {
      errors = adjusted_errors,
   } as lusc.ErrorGroup

   return setmetatable(this, 
      { __index = lusc.ErrorGroup, __tostring = function():string
            local lines = {}
            for _, err in ipairs(this.errors) do
               table.insert(lines, tostring(err))
            end
            return table.concat(lines, '\n')
         end,
      } as metatable<lusc.ErrorGroup>)
end

-- *********** Event ***********

function lusc.Event.new(runner:lusc._Runner):lusc.Event
   return setmetatable(
      {
         _runner = runner,
         is_set = false,
         _waiting_tasks = Queue(),
      } as lusc.Event,
      { __index = lusc.Event } as metatable<lusc.Event>)
end

function lusc.Event:set()
   if self.is_set then
      util.assert(self._waiting_tasks:empty())
   else
      self.is_set = true
      local running_task = self._runner:_try_get_running_task()

      while not self._waiting_tasks:empty() do
         local task = self._waiting_tasks:dequeue()
         util.assert(task ~= running_task)
         self._runner:_schedule_now(task)
      end
   end
end

function lusc.Event:await()
   if not self.is_set then
      local task = self._runner:_get_running_task()

      util.assert(not self._waiting_tasks:contains(task))
      self._waiting_tasks:enqueue(task)

      util.try {
         action = function():nil
            self._runner:_await_task_rescheduled()
         end,
         catch = function(err:any):nil
            -- Note that this may or may not remove a value,
            -- since it could have been rescheduled normally due to event
            -- being set, and then subsequently received a pending error
            self._waiting_tasks:remove_value(task)
            error(err)
         end
      }

      -- If it gets here then it was rescheduled from the set
      util.assert(not self._waiting_tasks:contains(task))
   end
end

-- *********** Task ***********

function lusc.Task.new(runner:lusc._Runner, task_handler:function(), nursery_owner:lusc.Nursery, opts:lusc.Task.Opts):lusc.Task
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
         _last_schedule_time = nil,
         _is_discarded = false,
         _is_scheduled = false,
         _min_shield_depth = nil,
         _coro = coroutine.create(task_handler),
         _nursery_owner = nursery_owner, -- null for root task
         _parent_task = parent_task,

         -- Use a separate field here to make it read only
         parent = parent_task,

         _wait_until = nil,
         _done = lusc.Event.new(runner),
         _pending_errors = {},
         _pending_cancellation_errors = {},
         _wake_for_pending_errors = true,
         _opts = opts or {},
         _runner = runner,
         _child_nursery_stack = {},
         _cancel_scope_stack = {},
         _debug_task_tree = nil,
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

function lusc.Task:_has_pending_errors():boolean
   return #self._pending_errors > 0 or not util.map_is_empty(self._pending_cancellation_errors)
end

function lusc.Task:_consider_scheduling_for_pending_errors()
   if self._wake_for_pending_errors then
      if self:_has_pending_errors() then
         self._runner:_schedule_now(self)
      else
         _log("Ignoring request to schedule task [%s] for pending error since no pending errors exist yet", self._debug_task_tree)
      end
   else
      _log("Ignoring request to schedule task [%s] for pending error due to wake_for_pending_errors flag", self._debug_task_tree)
   end
end

function lusc.Task:_save_shielded_error(err:lusc.CancelledError)
   util.assert(#self._cancel_scope_stack >= 1)

   local scope_to_use:lusc.CancelScope
   local start_index = 1

   if err._trigger_scope._task == self then
      local originating_index = err._trigger_scope._depth + 1
      -- Use the first shielded scope underneath the originating scope
      start_index = originating_index + 1
   end

   for i=start_index,#self._cancel_scope_stack do
      local candidate = self._cancel_scope_stack[i]

      if candidate._shielded then
         scope_to_use = candidate
         break
      end
   end

   util.assert(scope_to_use ~= nil)

   util.assert(scope_to_use._is_running)
   util.assert(scope_to_use._shielded)
   table.insert(scope_to_use._old_pending_errors, err)
end

function lusc.Task:_enqueue_cancellation_error(err:lusc.CancelledError)
   _log("Received cancellation error (depth %s) for task [%s] (min_shield_depth %s)", err._trigger_scope._depth, self._debug_task_tree, self._min_shield_depth)

   if self._min_shield_depth ~= nil and (err._trigger_scope._task ~= self or err._trigger_scope._depth < self._min_shield_depth) then
      self:_save_shielded_error(err)
      _log("Suppressed cancellation error for task [%s] due to min_shield_depth check - will restore this later", self._debug_task_tree)
      return
   end

   _log("Enqueued pending cancellation error %s for task %s", err, self._debug_task_tree)
   util.assert(self._pending_cancellation_errors[err] == nil)
   self._pending_cancellation_errors[err] = true
   self:_consider_scheduling_for_pending_errors()
end

function lusc.Task:_enqueue_pending_error(err:any)
   _log("Enqueued pending error %s for task %s", err, self._debug_task_tree)
   table.insert(self._pending_errors, err)
   self:_consider_scheduling_for_pending_errors()
end

-- *********** CancelledError ***********

function lusc.CancelledError.new(runner:lusc._Runner, trigger_scope: lusc.CancelScope):lusc.CancelledError
   util.assert(trigger_scope ~= nil)

   local name:string

   if runner._opts.generate_debug_names then
      name = string.format("<cancelled-s%s>", trigger_scope._id)
   else
      name = "<cancelled>"
   end

   local this = {
      _trigger_scope = trigger_scope,
   } as lusc.CancelledError

   return setmetatable(this, 
      { __index = lusc.CancelledError, __tostring = function():string return name end,
      } as metatable<lusc.CancelledError>)
end

-- *********** CancelScope ***********

function lusc.CancelScope.new(runner:lusc._Runner, task:lusc.Task, opts:lusc.CancelScope.Opts):lusc.CancelScope
   cancel_scope_counter = cancel_scope_counter + 1
   local id = cancel_scope_counter

   opts = opts or {}

   local shielded = opts.shielded

   if shielded == nil then
      shielded = false
   end

   local default_deadline_opts:lusc.DeadlineOpts = {
      move_on_after = opts.move_on_after,
      move_on_at = opts.move_on_at,
      fail_after = opts.fail_after,
      fail_at = opts.fail_at,
   }

   local debug_name = opts.name

   if debug_name == nil then
      if runner._opts.generate_debug_names then
         debug_name = string.format("s%s", id)
      else
         debug_name = "<cancel-scope>"
      end
   end

   return setmetatable(
      {
         _id = id,
         _runner = runner,
         _task = task,
         _debug_name = debug_name,
         _depth = #task._cancel_scope_stack,
         _old_pending_errors = {},
         _default_deadline_opts = default_deadline_opts,
         _children = {},
         _shielded = shielded,
         _cancel_error = nil,
         _has_cancelled = false,
         _hit_deadline = false,
         _deadline_task = nil,
         _cancel_observers = {},
         _fail_on_deadline = false,
         _is_running = false,
      } as lusc.CancelScope,
      { __index = lusc.CancelScope } as metatable<lusc.CancelScope>)
end

function lusc.CancelScope:_try_get_deadline_info(opts:lusc.DeadlineOpts):number, boolean
   local deadline:number
   local fail_on_deadline:boolean

   if opts.fail_at then
      util.assert(opts.move_on_after == nil and opts.move_on_at == nil and opts.fail_after == nil)
      deadline = opts.fail_at
      fail_on_deadline = true
   elseif opts.fail_after then
      util.assert(opts.move_on_after == nil and opts.move_on_at == nil)
      fail_on_deadline = true
      deadline = _get_time() + opts.fail_after
   elseif opts.move_on_at then
      util.assert(opts.move_on_after == nil)
      fail_on_deadline = false
      deadline = opts.move_on_at
   elseif opts.move_on_after then
      fail_on_deadline = false
      deadline = _get_time() + opts.move_on_after
   else
      deadline = nil
      fail_on_deadline = false
   end

   return deadline, fail_on_deadline
end

function lusc.CancelScope:_observe_cancel_request(callback:function(lusc.CancelledError))
   table.insert(self._cancel_observers, callback)
end

function lusc.CancelScope:cancel()
   -- Consider just doing a return in this case instead of assert
   util.assert(self._is_running, "[CancelScope] Attempted to cancel cancel scope that isn't running")

   if not self._has_cancelled then
      self._has_cancelled = true
      util.assert(self._cancel_error == nil)
      self._cancel_error = lusc.CancelledError.new(self._runner, self)
      self._task:_enqueue_cancellation_error(self._cancel_error)

      for _, observer in ipairs(self._cancel_observers) do
         observer(self._cancel_error)
      end

      for _, child in ipairs(self._children) do
         child:cancel()
      end
   end
end

function lusc.CancelScope:_set_deadline(opts:lusc.DeadlineOpts)
   util.assert(self._is_running)
   util.assert(not self._hit_deadline)
   util.assert(not self._has_cancelled)

   -- If setting multiple times is necessary then we can discard the existing task and restart it
   util.assert(self._deadline_task == nil, "Attempted to set cancel scope deadline multiple times")

   local deadline, fail_on_deadline = self:_try_get_deadline_info(opts)
   self._fail_on_deadline = fail_on_deadline

   if deadline == nil then
      _log("[CancelScope] No deadline set for cancel scope [%s]", self._debug_name)
   else
      _log("[CancelScope] Setting deadline for cancel scope [%s] to %.2f seconds from now", self._debug_name, deadline - _get_time())

      local task_name:string

      if self._runner._opts.generate_debug_names then
         task_name = string.format("deadline-%s-%s", self._task._debug_task_tree, self._debug_name)
      end

      self._deadline_task = self._runner:_create_new_task_and_schedule(function()
         lusc.await_until(deadline)
         util.assert(not self._hit_deadline)
         self._hit_deadline = true
         self:cancel()
      end, nil, nil, { name = task_name })
   end
end

function lusc.CancelScope:_run(handler:function(scope:lusc.CancelScope)):lusc.CancelScope.Result
   util.assert(not self._is_running)
   util.assert(self._task == self._runner:_get_running_task())

   local scope_stack = self._task._cancel_scope_stack
   local parent:lusc.CancelScope

   if #scope_stack > 0 then
      parent = scope_stack[#scope_stack]
      table.insert(parent._children, self)
   end

   table.insert(scope_stack, self)
   self._is_running = true
   _log("[CancelScope] Running cancel scope [%s]", self._debug_name)

   local old_min_shield_depth:integer
   local shielded = self._shielded

   if shielded then
      old_min_shield_depth = self._task._min_shield_depth
      util.assert(self._task._min_shield_depth == nil or self._task._min_shield_depth < self._depth)
      self._task._min_shield_depth = self._depth

      -- Cache the pending cancellations that don't apply to this scope then restore afterwards
      for cancel_err, _ in pairs(self._task._pending_cancellation_errors) do
         if cancel_err._trigger_scope._depth < self._depth then
            table.insert(self._old_pending_errors, cancel_err)
            self._task._pending_cancellation_errors[cancel_err] = nil
         end
      end

      -- This shouldn't be possible since they should always be popped before
      -- running our task
      util.assert(#self._task._pending_errors == 0)

      -- We might already have a cancel error enqueued, causing a schedule,
      -- so need to undo that
      if self._task._is_scheduled then
         self._runner:_unschedule_task(self._task)
      end
   end

   self:_set_deadline(self._default_deadline_opts)

   util.try {
      action = function():nil
         handler(self)
      end,
      catch = function(errors:any):nil
         if not _is_instance(errors, lusc.ErrorGroup) then
            _log("Propagating error in cancel scope [%s]: %s", self._debug_name, errors)
            error(errors)
         end

         local error_group = errors as lusc.ErrorGroup
         local self_err:lusc.CancelledError

         for _, err in ipairs(error_group.errors) do
            if _is_instance(err, lusc.CancelledError) then
               local cancel_err = err as lusc.CancelledError
               if cancel_err._trigger_scope == self then
                  util.assert(self_err == nil)
                  self_err = cancel_err
               end
            end
         end

         if self_err ~= nil then
            _log("Successfully swallowed self cancel error in scope [%s]", self._debug_name)
            util.remove_element(error_group.errors, self_err)
            self._has_cancelled = true
         end

         if #error_group.errors > 0 then
            _log("Propagating %s errors in cancel scope [%s]", #error_group.errors, self._debug_name)
            error(error_group)
         end
      end,
      finally = function():nil
         self._is_running = false

         if shielded then
            util.assert(self._task._min_shield_depth == self._depth)
            self._task._min_shield_depth = old_min_shield_depth

            for _, cancel_err in ipairs(self._old_pending_errors) do
               util.assert(self._task._pending_cancellation_errors[cancel_err] == nil)
               self._task._pending_cancellation_errors[cancel_err] = true
            end

            self._task:_consider_scheduling_for_pending_errors()
         end

         util.assert(scope_stack[#scope_stack] == self)
         table.remove(scope_stack)

         if parent ~= nil then
            local last_child = table.remove(parent._children)
            util.assert(last_child == self)
         end

         if self._deadline_task ~= nil then
            self._runner:_discard_task(self._deadline_task)
         end

         for cancel_err, _ in pairs(self._task._pending_cancellation_errors) do
            if cancel_err._trigger_scope == self then
               self._task._pending_cancellation_errors[cancel_err] = nil
            end
         end
      end,
   }

   if self._hit_deadline and self._fail_on_deadline then
      error("Lusc cancel scope reached given failure deadline")
   end

   _log("[CancelScope] Completed running cancel scope [%s] without errors (has_cancelled = '%s', hit_deadline = '%s')", self._debug_name, self._has_cancelled, self._hit_deadline)

   return {
      was_cancelled = self._has_cancelled,
      hit_deadline = self._hit_deadline,
   }
end

-- *********** Nursery ***********

function lusc.Nursery.new(runner:lusc._Runner, task:lusc.Task, opts:lusc.Nursery.Opts):lusc.Nursery
   util.assert(task ~= nil)

   nursery_counter = nursery_counter + 1

   local cancel_scope_opts = {
      shielded = opts.shielded,
      move_on_after = opts.move_on_after,
      move_on_at = opts.move_on_at,
      fail_after = opts.fail_after,
      fail_at = opts.fail_at,
   }

   local id = nursery_counter
   local name = opts.name

   if name == nil then
      if runner._opts.generate_debug_names then
         name = string.format('n%s', id)
      else
         name = '<nursery>'
      end
   end

   return setmetatable(
      {
         _id = nursery_counter,
         _runner = runner,
         _task = task,
         _name = name,
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
         cancel_scope = lusc.CancelScope.new(runner, task, cancel_scope_opts),
      } as lusc.Nursery,
      { __index = lusc.Nursery } as metatable<lusc.Nursery>)
end

function lusc.Nursery:_cancel_sub_tasks(err:lusc.CancelledError)
   util.assert(not self._is_closed, "Attempted to cancel closed nursery [%s]", self._debug_nursery_tree)
   _log("Cancelling all sub tasks in nursery [%s]", self._debug_nursery_tree)

   for task, _ in pairs(self._child_tasks) do
      task:_enqueue_cancellation_error(err)
   end

   for nursery, _ in pairs(self._child_nurseries) do
      if not nursery.cancel_scope._shielded then
         nursery:_cancel_sub_tasks(err)
      end
   end
end

function lusc.Nursery:initialize()
   util.assert(not self._is_closed)

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
      self._debug_nursery_tree = self._parent_nursery._debug_nursery_tree .. "." .. self._name
   else
      self._debug_nursery_tree = self._name
   end

   self.cancel_scope:_observe_cancel_request(function(err:lusc.CancelledError)
      self:_cancel_sub_tasks(err)
   end)

   _log("Created new nursery [%s]", self._debug_nursery_tree)
end

function lusc.Nursery:start_soon(task_handler:function(), opts:lusc.Task.Opts)
   if self.cancel_scope._has_cancelled then
      _log("Attempted to start new task in nursery [%s] after it was already cancelled - ignoring request", self._debug_nursery_tree)
      return
   end

   util.assert(not self._is_closed, "Cannot add tasks to closed nursery")
   local task = self._runner:_create_new_task_and_schedule(task_handler, self, nil, opts)
   util.assert(self._child_tasks[task] == nil)
   self._child_tasks[task] = true
end

function lusc.Nursery:close(nursery_err:any):lusc.CancelScope.Result
   util.assert(not self._is_closed)
   util.assert(self._task == self._runner:_get_running_task())

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

   -- In some cases we can already be scheduled for the next event loop
   -- (eg. our cancel scope is cancelled just before the nursery is closed)
   -- We don't want to wake up though except when all our sub tasks are done,
   -- so need to unschedule ourselves here, then use _wake_for_pending_errors flag
   -- to protect against getting scheduled again
   if self._task._is_scheduled then
      self._runner:_unschedule_task(self._task)
   end

   -- Block this task using wake_for_pending_errors flag until 
   -- all child tasks done. Defer any exceptions until after all 
   -- children are done
   util.assert(self._task._wake_for_pending_errors)
   self._task._wake_for_pending_errors = false

   local all_errors = {}

   if nursery_err ~= nil then
      table.insert(all_errors, nursery_err)
   end

   -- Note that the task loop will call cancel() for us here when one of these child tasks fail
   -- Note also that more child tasks can be added while we are iterating over the list
   while not util.map_is_empty(self._child_tasks) do
      for child_task, _ in pairs(self._child_tasks) do
         util.try {
            action = function():nil
               _log("Nursery [%s] waiting for child task [%s] to complete...", self._debug_nursery_tree, child_task._debug_task_tree)
               child_task._done:await()
            end,
            catch = function(child_err:any):nil
               _log("Encountered error while waiting for task [%s] to complete while closing nursery [%s].  Will propagate it. Details: '%s'\n", child_task._debug_task_tree, self._debug_nursery_tree, child_err)
               table.insert(all_errors, child_err)
            end,
            finally = function():nil
               util.assert(child_task._done.is_set)
               util.assert(self._child_tasks[child_task] == nil)
               _log("Nursery [%s] finished waiting for child task [%s]", self._debug_nursery_tree, child_task._debug_task_tree)
            end,
         }
      end
   end

   self._is_closed = true
   util.assert(util.map_is_empty(self._child_nurseries), "[lusc][%s] Found non empty list of child nurseries at end of closing nursery [%s]", self._debug_task_tree, self._debug_nursery_tree)

   util.assert(not self._task._wake_for_pending_errors)
   self._task._wake_for_pending_errors = true

   for _, err in ipairs(self._task:_pop_pending_errors()) do
      table.insert(all_errors, err)
   end

   for err, _ in pairs(self._task._pending_cancellation_errors) do
      table.insert(all_errors, err)
   end

   if self._parent_nursery ~= nil then
      _log("Removing nursery [%s] from parents child nurseries list", self._debug_nursery_tree)
      self._parent_nursery._child_nurseries[self] = nil
   else
      _log("No parent nursery found for [%s], so no need to remove from child nurseries list", self._debug_nursery_tree)
   end

   local nursery_stack = self._task._child_nursery_stack
   util.assert(nursery_stack[#nursery_stack] == self)
   table.remove(nursery_stack)

   if #all_errors > 0 then
      _log("Closed nursery [%s] with %s errors", self._debug_nursery_tree, #all_errors)
      error(lusc.ErrorGroup.new(all_errors), 0)
   end

   _log("Successfully fully closed nursery [%s]", self._debug_nursery_tree)
end

function lusc.Nursery:_run(handler:function(lusc.Nursery)):lusc.CancelScope.Result
   return self.cancel_scope:_run(function()
      local main_err:any
      util.try {
         action = function():nil
            handler(self)
         end,
         catch = function(e:any):nil
            _log("Received error in main function of nursery '%s': %s", self._debug_nursery_tree, e)
            self.cancel_scope:cancel()
            main_err = e
         end,
      }
      self:close(main_err)
   end)
end

-- *********** _Runner ***********

function lusc._Runner.new(opts:lusc.Opts):lusc._Runner
   util.assert(opts ~= nil, "No options provided to lusc")

   local scheduler:lusc.Scheduler

   if opts.scheduler_factory == nil then
      scheduler = lusc.DefaultScheduler.new() as lusc.Scheduler
   else
      scheduler = opts.scheduler_factory()
      util.assert(scheduler ~= nil)
   end

   return setmetatable(
      {
         _tasks_by_coro = {},
         _task_queue = {},
         _has_started = false,
         _has_stopped = false,
         _main_nursery = nil,
         _main_task = nil,
         _opts = opts,
         _is_within_task_loop = false,
         _stop_requested_event = nil,
         _root_error = nil,
         _initial_handlers = {},
         _next_step_time = nil,
         _scheduler = scheduler,
         _main_nursery_deadline_opts = nil,
      } as lusc._Runner,
      { __index = lusc._Runner } as metatable<lusc._Runner>)
end

function lusc._Runner:_check_errored()
   util.assert(self._root_error == nil, "lusc has already encountered an error, cannot continue.  See log above for details.")
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

   local index = _binary_search(self._task_queue, task, comparator)
   util.assert(index >= 1 and index <= #self._task_queue + 1)
   return index
end

--- Note that the return value can be negative
function lusc._Runner:_try_get_time_to_next_task():number
   if #self._task_queue == 0 then
      return nil
   end

   return self._task_queue[#self._task_queue]._wait_until - _get_time()
end

function lusc._Runner:_enqueue_step_in(delay:number)
   util.assert(delay ~= nil and delay >= 0)

   local current_time = _get_time()
   local max_time = current_time + delay

   if self._next_step_time ~= nil and self._next_step_time < max_time then
      local time_remaining = self._next_step_time - current_time
      _log("Received request to enqueue step function but ignoring since it is already scheduled to run in %.2f seconds", time_remaining)
      return
   end

   self._next_step_time = current_time + delay
   self._scheduler:schedule(self._next_step_time, function()
      util.try {
         action = function():nil
            local new_time = _get_time()
            util.assert(new_time >= self._next_step_time, "Scheduler returned %s seconds earlier than expected", self._next_step_time - new_time)
            self._next_step_time = nil
            self:_step()
         end,
         catch = function(err):nil
            -- It's important that we log any errors here because otherwise luv
            -- will silently swallow the exception
            _log("Encountered error during lusc update.  This suggests a bug in lusc itself.  Details:\n%s", err)
            -- We intentionally do not re-throw the error here, because
            -- this seems to somehow block luv from closing

            -- This kind of error is fatal so just shut down the whole thing
            -- Necessary when running multiple tests at once
            lusc._current_runner = nil
         end
      }
   end)

   _log("Scheduled event loop to run again in %.2f seconds", delay)
end

function lusc._Runner:_enqueue_step_now()
   self:_enqueue_step_in(0)
end

function lusc._Runner:_schedule_task(task:lusc.Task, new_wait_until:number)
   util.assert(not task._done.is_set)

   local current_time = _get_time()

   if task._is_scheduled then
      if task._wait_until < current_time then
         _log("Attempted to schedule task [%s] twice - ignoring new request since existing schedule is older", task._debug_task_tree)
         return
      end

      self:_unschedule_task(task)
   end

   util.assert(not task._is_scheduled)
   task._is_scheduled = true
   task._wait_until = new_wait_until

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
   util.assert(self._task_queue[index] ~= task)
   table.insert(self._task_queue, index, task)

   -- This can get called by code outside of lusc (event.set())
   -- and might require that we wake it up
   if not self._is_within_task_loop then
      self:_enqueue_step_now()
   end
end

function lusc._Runner:_schedule_now(task:lusc.Task)
   self:_schedule_task(task, _get_time())
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

function lusc._Runner:_await_until(until_time:number)
   self:_check_errored()
   util.assert(self._is_within_task_loop)
   _log("Calling coroutine.yield to wait for %.2f seconds", until_time - _get_time())
   self:_checkpoint(until_time)
end

function lusc._Runner:_await_sleep(seconds:number)
   self:_check_errored()
   assert(seconds >= 0)
   self:_await_until(_get_time() + seconds)
end

function lusc._Runner:_await_forever()
   self:_check_errored()
   self:_await_until(math.huge)
end

function lusc._Runner:_create_new_task_and_schedule(task_handler:function(), nursery_owner:lusc.Nursery, wait_until:number, opts:lusc.Task.Opts):lusc.Task
   if wait_until == nil then
      wait_until = _get_time()
   end
   local task = lusc.Task.new(self, task_handler, nursery_owner, opts)
   task:initialize()
   util.assert(task._coro ~= nil)
   self._tasks_by_coro[task._coro] = task
   self:_schedule_task(task, wait_until)
   return task
end

function lusc._Runner:_on_task_errored(task:lusc.Task, error_obj:any)
   if self:_is_cancelled_error(error_obj) then
      -- For cancelled errors, we do not want to propagate it back up
      -- All other errors though we do
      _log("Received cancelled error from task [%s]", task._debug_task_tree)
      return
   end

   -- Must grab the traceback before unwinding stack for some reason
   local traceback = debug.traceback(task._coro)

   _log("Received error from task [%s]. Will propagate it. Details: %s", task._debug_task_tree, error_obj)

   if task == self._main_task then
      util.assert(self._root_error == nil)
      self._root_error = lusc.ErrorGroup.new({error_obj, traceback})
      self._stop_requested_event:set()
   else
      -- Here, we want to propagate errors up in the task/nursery stack and then
      -- trigger cancellation in current nursery and below

      local nursery = task._nursery_owner
      util.assert(nursery ~= nil)
      nursery.cancel_scope:cancel()

      task._parent_task:_enqueue_pending_error(error_obj)
      task._parent_task:_enqueue_pending_error(traceback)
   end
end

function lusc._Runner:_is_cancelled_error(err:any):boolean
   if _is_instance(err, lusc.ErrorGroup) then
      -- Note that the logic in ErrorGroup should guarantee that we don't 
      -- get duplicate instances of cancelled here
      local sub_errors = (err as lusc.ErrorGroup).errors
      util.assert(#sub_errors > 0)
      for _, sub_err in ipairs(sub_errors) do
         if not _is_instance(sub_err, lusc.CancelledError) then
            return false
         end
      end
      return true
   end

   return false
end

function lusc._Runner:_discard_task(task:lusc.Task)
   if task._is_discarded then
      return
   end

   if task._is_scheduled then
      self:_unschedule_task(task)
   end

   if task._nursery_owner ~= nil then
      task._nursery_owner._child_tasks[task] = nil
   end
   self._tasks_by_coro[task._coro] = nil
   task._done:set()

   util.assert(#task._child_nursery_stack == 0)
   util.assert(#task._cancel_scope_stack == 0)
   util.assert(task._min_shield_depth == nil)

   task._is_discarded = true
end

function lusc._Runner:_run_task(task:lusc.Task)
   if task._is_discarded then
      -- TODO - how does this happen sometimes?
      return
   end

   util.assert(not task._done.is_set, "Attempted to run task [%s] but it is already marked as done", task._debug_task_tree)

   local pending_errors = task:_pop_pending_errors()

   for err, _ in pairs(task._pending_cancellation_errors) do
      table.insert(pending_errors, err)
   end

   local coro_arg:any
   if #pending_errors > 0 then
      coro_arg = lusc.ErrorGroup.new(pending_errors)
      _log("Resuming task [%s] with %s pending errors", task._debug_task_tree, #pending_errors)
   else
      _log("Resuming task [%s]", task._debug_task_tree)
      coro_arg = _NO_ERROR
   end

   local resume_status, resume_result = coroutine.resume(task._coro, coro_arg)
   local coro_status = coroutine.status(task._coro)

   if not resume_status then
      util.assert(coro_status == 'dead')
      self:_on_task_errored(task, resume_result)
   end

   if coro_status == 'dead' then
      _log("Detected task [%s] coroutine as dead", task._debug_task_tree)
      self:_discard_task(task)
   else
      if resume_result == _TASK_PAUSE then
         _log("Pausing task [%s]", task._debug_task_tree)
      else
         self:_schedule_task(task, resume_result as number)
      end

      if not util.map_is_empty(task._pending_cancellation_errors) then
         task:_consider_scheduling_for_pending_errors()
      end
   end
end

function lusc._Runner:_create_nursery(opts:lusc.Nursery.Opts):lusc.Nursery
   opts = opts or {}

   local current_task = self:_get_running_task()
   local current_nursery = current_task:_try_get_current_nursery()

   if not opts.shielded and current_nursery ~= nil and current_nursery.cancel_scope._has_cancelled then
      error(current_nursery.cancel_scope._cancel_error)
   end

   local nursery = lusc.Nursery.new(self, current_task, opts)
   nursery:initialize()
   return nursery
end

function lusc._Runner:_run_nursery(handler:function(lusc.Nursery), opts:lusc.Nursery.Opts):lusc.CancelScope.Result
   util.assert(self._is_within_task_loop)
   return self:_create_nursery(opts):_run(handler)
end

function lusc._Runner:_unschedule_task(task:lusc.Task)
   util.assert(task._is_scheduled)
   local index = self:_find_task_index(task)
   util.assert(self._task_queue[index] == task)
   table.remove(self._task_queue, index)
   task._is_scheduled = false
end

function lusc._Runner:_process_tasks()
   util.assert(self._is_within_task_loop)
   local task_queue = self._task_queue

   while #task_queue > 0 do
      local time_to_wait = self:_try_get_time_to_next_task()

      if time_to_wait == nil or time_to_wait > 0 then
         -- Nothing else to do for now
         break
      end

      util.assert(not self._root_error)

      -- Collect batch of tasks which are ready to run or have pending error
      local current_time = _get_time()
      local pending_error_tasks_to_run = {}
      local tasks_to_run = {}

      -- Tasks that have the same wait_until time will be ordered by their
      -- id, which is not ideal, but should be rare since in most cases
      -- tasks should have a unique wait_until value
      -- Also, id will at least order by creation time
      while #task_queue > 0 and task_queue[#task_queue]._wait_until - current_time <= 0 do
         local task = table.remove(task_queue)
         _log("Removed task [%s] from run queue", task._debug_task_tree)
         util.assert(not task._done.is_set)
         util.assert(task._is_scheduled)
         task._is_scheduled = false

         if task:_has_pending_errors() then
            -- Execute tasks with pending errors first since they
            -- might cancel the other tasks, so save us some work
            table.insert(pending_error_tasks_to_run, task)
         else
            table.insert(tasks_to_run, task)
         end
      end

      for _, task in ipairs(pending_error_tasks_to_run) do
         self:_run_task(task)
      end

      for _, task in ipairs(tasks_to_run) do
         self:_run_task(task)
      end
   end
end

function lusc._Runner:_get_root_nursery():lusc.Nursery
   return self._main_nursery
end

function lusc._Runner:_cancel_all()
   self._main_nursery.cancel_scope:cancel()
end

function lusc._Runner:_stop_requested():boolean
   return self._stop_requested_event.is_set
end

function lusc._Runner:_stop(deadline_opts:lusc.DeadlineOpts)
   util.assert(self._has_started)

   deadline_opts = deadline_opts or {}

   if self._has_stopped then
      util.assert(self._stop_requested_event.is_set)
      _log("Received request for stop() but stop has already completed")
      return
   end

   if self._stop_requested_event.is_set then
      _log("Received request for stop() but stop is already in progress (possibly due to an error)")
   else
      _log("Received request for stop().  Will end once tasks complete")
      util.assert(not self._has_stopped)

      -- This should wake up the task loop to continue main task and close main nursery
      -- note that this might already have been set due to an error
      self._stop_requested_event:set()
   end

   if self._main_nursery == nil then
      self._main_nursery_deadline_opts = deadline_opts
   else
      -- This should be a no-op when none of these are set
      self._main_nursery.cancel_scope:_set_deadline(deadline_opts)
   end
end

function lusc._Runner:_schedule(handler:function(), opts:lusc.Task.Opts)
   self:_check_errored()
   util.assert(self._has_started)
   -- util.assert(not self._is_within_task_loop)

   if self._main_nursery == nil then
      table.insert(self._initial_handlers, {handler, opts})
   else
      -- This will wake up our task loop since it calls schedule_task
      self._main_nursery:start_soon(handler, opts)
   end
end

function lusc._Runner:_step()
   util.assert(not self._is_within_task_loop)
   self._is_within_task_loop = true
   self:_process_tasks()
   util.assert(self._is_within_task_loop)
   self._is_within_task_loop = false

   if self._root_error then
      util.assert(self._stop_requested_event.is_set)
   end

   local time_to_wait = self:_try_get_time_to_next_task()

   if time_to_wait == nil then
      -- No tasks in queue, don't restart timer

      if self._stop_requested_event.is_set then
         if util.map_is_empty(self._tasks_by_coro) then
            util.assert(#self._task_queue == 0)
            util.assert(self._main_task._done.is_set)
            self._main_task = nil
            self._main_nursery = nil
            util.assert(not self._has_stopped)
            self._has_stopped = true
            self._scheduler:dispose()
            util.assert(self._opts.on_completed ~= nil)
            self._opts.on_completed(self._root_error)
         else
            _log("Stop requested but tasks have not completed, despite task queue being empty.  One explanation is that we are waiting to be woken up by another luv process")
         end
      else
         _log("No more tasks ready in queue, and no next time found. Will wait to be woken up by another event or new task schedule")
      end
   else
      self:_enqueue_step_in(math.max(0, time_to_wait))
   end
end

function lusc._Runner:_open_channel<T>(max_buffer_size:integer):lusc.Channel<T>
   local impl:ChannelImpl<T> = ChannelImpl.new(self, max_buffer_size)
   return impl as lusc.Channel<T>
end

function lusc._Runner:_new_event():lusc.Event
   self:_check_errored()
   return lusc.Event.new(self)
end

function lusc._Runner:_cancel_scope(handler:function(scope:lusc.CancelScope), opts:lusc.CancelScope.Opts):lusc.CancelScope.Result
   util.assert(self._is_within_task_loop)
   local task = self:_get_running_task()
   return lusc.CancelScope.new(self, task, opts):_run(handler)
end

function lusc._Runner:_start()
   util.assert(not self._has_started)
   util.assert(self._main_task == nil)
   util.assert(self._main_nursery == nil)
   util.assert(self._stop_requested_event == nil)
   util.assert(not self._is_within_task_loop)

   self._stop_requested_event = lusc.Event.new(self)

   self._main_task = self:_create_new_task_and_schedule(function()
      self:_run_nursery(function(nursery:lusc.Nursery)
         util.assert(self._main_nursery == nil)
         self._main_nursery = nursery

         if self._main_nursery_deadline_opts ~= nil then
            nursery.cancel_scope:_set_deadline(self._main_nursery_deadline_opts)
         end

         for _, info in ipairs(self._initial_handlers) do
            nursery:start_soon(info[1], info[2])
         end
         self._initial_handlers = {}
         self._stop_requested_event:await()
      end, { name = "n-main" })
   end, nil, nil, { name = "t-main" })

   self._has_started = true
end

-- *********** lusc ***********

function lusc._get_runner():lusc._Runner
   local result = lusc._current_runner
   util.assert(result ~= nil, "[lusc] Attempted to use lusc but it has not been started")
   return result
end

function lusc.open_nursery(handler:function(nursery:lusc.Nursery), opts:lusc.Nursery.Opts):lusc.CancelScope.Result
   return lusc._get_runner():_run_nursery(handler, opts)
end

-- returns fractional time in seconds from an arbitrary reference point
function lusc.get_time():number
   return _get_time()
end

function lusc.await_sleep(seconds:number)
   lusc._get_runner():_await_sleep(seconds)
end

function lusc.await_until(until_time:number)
   lusc._get_runner():_await_until(until_time)
end

function lusc.await_forever()
   lusc.await_until(math.huge)
end

function lusc.new_event():lusc.Event
   return lusc._get_runner():_new_event()
end

function lusc.get_running_task():lusc.Task
   return lusc._get_runner():_get_running_task()
end

function lusc.try_get_running_task():lusc.Task
   return lusc._get_runner():_try_get_running_task()
end

function lusc.open_channel<T>(max_buffer_size:integer):lusc.Channel<T>
   return lusc._get_runner():_open_channel(max_buffer_size)
end

function lusc.schedule(handler:function(), opts:lusc.Task.Opts)
   lusc._get_runner():_schedule(handler, opts)
end

function lusc.schedule_wrap(handler:function(...:any), opts:lusc.Task.Opts):function(...:any)
   return function(...:any)
      local args = {...}
      lusc._get_runner():_schedule(function()
         handler(table.unpack(args))
      end, opts)
   end
end

function lusc.stop_requested():boolean
   return lusc._get_runner():_stop_requested()
end

function lusc.stop(opts:lusc.DeadlineOpts)
   lusc._get_runner():_stop(opts)
end

function lusc.cancel_all()
   lusc._get_runner():_cancel_all()
end

function lusc.has_started():boolean
   return lusc._current_runner ~= nil
end

function lusc.is_processing():boolean
   return lusc._current_runner ~= nil and lusc._current_runner._is_within_task_loop
end

function lusc.get_root_nursery():lusc.Nursery
   return lusc._get_runner():_get_root_nursery()
end

function lusc.is_cancelled_error(err:any):boolean
   return lusc._get_runner():_is_cancelled_error(err)
end

function lusc.cancel_scope(handler:function(scope:lusc.CancelScope), opts:lusc.CancelScope.Opts):lusc.CancelScope.Result
   return lusc._get_runner():_cancel_scope(handler, opts)
end

function lusc.move_on_after(delay_seconds:number, handler:function(scope:lusc.CancelScope), opts:lusc.CancelScope.ShortcutOpts):lusc.CancelScope.Result
   opts = opts or {}
   return lusc.cancel_scope(handler, { move_on_after = delay_seconds, shielded = opts.shielded, name = opts.name })
end

function lusc.move_on_at(delay_seconds:number, handler:function(scope:lusc.CancelScope), opts:lusc.CancelScope.ShortcutOpts):lusc.CancelScope.Result
   opts = opts or {}
   return lusc.cancel_scope(handler, { move_on_at = delay_seconds, shielded = opts.shielded, name = opts.name })
end

function lusc.fail_after(delay_seconds:number, handler:function(scope:lusc.CancelScope), opts:lusc.CancelScope.ShortcutOpts):lusc.CancelScope.Result
   opts = opts or {}
   return lusc.cancel_scope(handler, { fail_after = delay_seconds, shielded = opts.shielded, name = opts.name })
end

function lusc.fail_at(delay_seconds:number, handler:function(scope:lusc.CancelScope), opts:lusc.CancelScope.ShortcutOpts):lusc.CancelScope.Result
   opts = opts or {}
   return lusc.cancel_scope(handler, { fail_at = delay_seconds, shielded = opts.shielded, name = opts.name })
end

function lusc.start(opts:lusc.Opts)
   opts = opts or {}

   local new_opts = util.shallow_clone(opts)
   new_opts.on_completed = function(root_error:lusc.ErrorGroup)
      util.assert(lusc._current_runner ~= nil)
      lusc._current_runner = nil

      if opts.on_completed then
         opts.on_completed(root_error)
      elseif root_error ~= nil then
         _log("Aborted lusc due to error:\n%s", root_error)
      end
   end

   util.assert(lusc._current_runner == nil, "Cannot call lusc.run from within another lusc.run")
   lusc._current_runner = lusc._Runner.new(new_opts)
   lusc._current_runner:_start()
end

return lusc

