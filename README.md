
Lusc - Structured Async/Concurrency for Lua
-----

Lusc brings the concepts of [Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) to Lua.  The name is an abbrevriation of this (**LU**a **S**tructured **C**oncurrency).

This programming paradigm was first popularized by the python library [Trio](https://github.com/python-trio/trio) and Lusc basically mirrors the Trio API except in Lua.  So if you are already familiar with Trio then you should be able to immediately understand the Lusc API.

If you aren't familiar with Trio, and also aren't familiar with [Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency), then it might be a good idea to read some of the [trio docs](https://trio.readthedocs.io/en/stable/reference-core.html) since they are much better than what you'll read here.

Simple Examples
---

Run multiple tasks in parallel:

```lua
local lusc = require("lusc")

local function main()
   print("Waiting 1 second...")
   lusc.await_sleep(1)

   print("Creating child tasks...")

   -- This will run both child tasks in parallel, so
   -- the total time will be 1 second, not 2
   lusc.open_nursery(function(nursery)
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
   -- Note that the nursery will block here until all child tasks complete

   print("Completed all child tasks")
end
```

Running the examples
---

You might notice that in the examples above, we are not calling the `main()` functions directly.  This is because, similar to trio, these all need to be executed underneath a `lusc.run` function.  However, unlike Trio, in order to call this function, the user has to supply implementations for `sleep` and `get_time` functions, since these vary depending on the environment where you are running Lua.

Therefore `lusc.run` returns a coroutine that yields with the number of seconds to sleep, and so the calling code needs to handle that.

If running in a Linux/OSX environment a simple way to achieve this would be the following (which you can execute for yourself by running the lua files in the `examples/` folder):

```lua
-- NOTE: Do not use this function in a real app
local function run(entry_point:function(lusc.Nursery))
   local pending_jobs = {entry_point}
   local coro = lusc.run {
      time_provider = function():number
         return os.time()
      end,
   }

   while true do
      local ok, result = coroutine.resume(coro, pending_jobs)
      pending_jobs = {}

      if not ok then
         error(result)
      end

      if result == lusc.NO_MORE_TASKS_SIGNAL then
         break
      end

      local seconds = result as number
      os.execute("sleep " .. tostring(seconds))
   end
end

run(main)
```

However - This approach has many limitations:
* `os.time()` does not provide sub-second precision
* `os.execute("sleep x")` is not cross platform (windows would require a different command)
* Using `os.execute` for sleep is a fairly heavy operation

Instead, you should use lusc on top of something else that can provide better implementations for sleep() and time_provider.

For example, if you are ok with adding a dependency to [Luv](https://github.com/luvit/luv) you can use [lusc_luv](https://github.com/svermeulen/lusc_luv) to provide wrap the `lusc.run` function for you

API Reference
---

```lua

-- NOTE - The code here is not valid Lua code - it is Teal code, which gets
-- compiled to Lua
-- But can be used as reference for your lua code to understand the API and the methods/types
local record lusc
   -- Pass QUIT_SIGNAL this to the lusc.run coroutine.resume
   QUIT_SIGNAL:any

   -- yielded by the lusc.run coroutine to indicate that all tasks have completed
   NO_MORE_TASKS_SIGNAL:any

   -- Parameter for lusc.run method
   record Opts
      -- When true, will generate unique names for all tasks and nurseries, which
      -- you can see by enabling logging with lusc.set_log_handler
      -- Default: false
      generate_debug_names:boolean

      -- Required function provided by user
      -- Should return fractional time in seconds from an arbitrary reference point
      time_provider:function():number
   end

   -- When running multiple tasks in parallel, it is possible for multiple
   -- errors to occur at once, therefore ErrorGroup is used to group all these
   -- errors together and propagate them all at the same time
   record ErrorGroup
      -- The list of all errors encountered
      errors:{any}
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
   run:function(opts:Opts):thread

   -- Pass in a custom log method here to get extra debugging info to see
   -- what all your nurseries/tasks are doing
   set_log_handler:function(log_handler:function(string))

   new_event:function():Event

   -- See trio docs for more info on these:
   await_forever:function()
   await_until_time:function(until_time:number)
   await_sleep:function(seconds:number)
   get_current_time:function():number
   open_nursery:function(handler:function(nursery:Nursery), opts:Nursery.Opts):Nursery.Result
end

return lusc
```

# Strong Typing Support

Note that this library is implemented using [Teal](https://github.com/teal-language/tl) and that all the lua files here are generated.  If you are also using Teal, and want your calls to the text-to-colorscheme API strongly typed, you can copy and paste the teal type definition files from `/dist/lusc.d.tl` into your project (or just add a path directly to the source code here in your tlconfig.lua file)

History / Credits
---

This library is based on [this great series](https://gist.github.com/belm0/4c6d11f47ccd31a231cde04616d6bb22) of articles explaining how to add structured concurrency support to Lua by @belm0.  One difference with the implementation provided in the article is that this library is compatible with Lua 5.1 (since it does not use to-be-closed variables).  This was necessary to provide LuaJIT compatibility.

