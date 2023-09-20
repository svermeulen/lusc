
-- Public API for local
-- When using teal with lusc, you can copy and paste this file into your project for strong type checks
-- Or use lusc source code directly instead
local record lusc
   QUIT_SIGNAL:any
   NO_MORE_TASKS_SIGNAL:any

   record Opts
      -- Default: false
      generate_debug_names:boolean

      -- should returns fractional time in seconds from an arbitrary reference point
      time_provider:function():number
   end

   record ErrorGroup
   end

   record Task
      record Opts
         name:string
      end
   end

   record Event
      is_set:boolean
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

      cancel:function(self: Nursery)
      start_soon:function(self: Nursery, func:function(), Task.Opts):Task
   end

   run:function(opts:Opts):thread
   set_log_handler:function(log_handler:function(string))
   new_event:function():Event
   await_forever:function()
   await_until_time:function(until_time:number)
   await_sleep:function(seconds:number)
   get_current_time:function():number
   open_nursery:function(handler:function(nursery:Nursery), opts:Nursery.Opts):Nursery.Result
end

return lusc
