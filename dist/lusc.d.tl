
-- Public API for Lusc
-- When using teal with lusc, you can copy and paste this file into your project for strong type checks
-- Or use lusc source code directly instead
local record lusc
   -- Parameter for lusc.run method
   record Opts
      -- When true, will generate unique names for all tasks and nurseries, which
      -- you can see by enabling logging with lusc.set_log_handler
      -- Default: false
      generate_debug_names:boolean

      -- Required function provided by user
      -- Should return fractional time in seconds from an arbitrary reference point
      time_provider:function():number

      -- Should sleep the given number of seconds
      sleep_handler:function(seconds:number)

      -- The entry point for your app.  Can optionally take the main nursery
      entry_point:function(Nursery)
   end

   -- When running multiple tasks in parallel, it is possible for multiple
   -- errors to occur at once, therefore ErrorGroup is used to group all these
   -- errors together and propagate them all at the same time
   record ErrorGroup
      -- The list of all errors encountered
      errors:{any}

      new:function({any}):ErrorGroup
   end

   -- Task = single coroutine of execution
   -- Always attached to a nursery
   -- See trio docs for more details
   record Task
      record Opts
         name:string
      end
   end

   -- Event can be used to communicate between separate tasks
   -- See trio docs for more details
   record Event
      is_set:boolean
      set:function(Event)
      await:function(Event)
   end

   -- Nursery is a group of tasks running in parallel
   -- See trio docs for more details
   record Nursery
      record Opts
         name:string

         -- When true, all tasks underneath this nursery
         -- will not be cancelled when any parent of this nursery is 
         -- cancelled, and therefore can be used for async cleanup logic
         -- See trio docs for more details
         shielded: boolean

         -- Note: can only set one of the following for a given nursery
         -- Use move_on_after to auto-cancel after a timeout
         move_on_after:number
         move_on_at:number

         -- Use fail_after to auto-cancel after a timeout, and also trigger an error afterwards
         fail_after:number
         fail_at:number
      end

      -- Return value of open_nursery
      -- Can be used to check if timeout was hit
      record Result
         was_cancelled: boolean
         hit_deadline: boolean
      end

      -- Cancel all tasks in nursery and also cancel all child nurseries
      -- Note that cancellation is async so will still need to wait after
      -- calling this
      -- See trio docs for more details
      cancel:function(self: Nursery)

      -- Schedule the given function to be executed in a new task/coroutine
      start_soon:function(self: Nursery, func:function(), Task.Opts):Task
   end

   -- Entry point for lusc
   run:function(opts:Opts)

   -- Pass in a custom log method here to get extra debugging info to see
   -- what all your nurseries/tasks are doing
   set_log_handler:function(log_handler:function(string))

   new_event:function():Event

   -- See trio docs for more info on these:
   await_forever:function()
   await_until_time:function(until_time:number)
   await_sleep:function(seconds:number)
   get_time:function():number
   open_nursery:function(handler:function(nursery:Nursery), opts:Nursery.Opts):Nursery.Result
end

return lusc
