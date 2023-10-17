
# Lusc - Structured Async/Concurrency for Lua

Lusc brings the concepts of [Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) to Lua.  The name is an abbrevriation of this (**LU**a **S**tructured **C**oncurrency).

This programming paradigm was first popularized by the python library [Trio](https://github.com/python-trio/trio) and Lusc basically mirrors the Trio API almost exactly.  So if you are already familiar with Trio then you should be able to immediately understand and use the Lusc API.

If you aren't familiar with Trio - then in short, Structured Concurrency makes asynchronous tasks an order of magnitude easier to manage.  It achieves this by making the structure of code match the hierarchical structure of the async operations, which results in many benefits.  For more details, you might check out the [trio docs](https://trio.readthedocs.io/en/stable/reference-core.html), or [these articles](https://gist.github.com/belm0/4c6d11f47ccd31a231cde04616d6bb22) (which this library was based on)

Installation
---

`luarocks install lusc`

Compatibility
---

Lusc is written in pure Lua, so should work on Linux/OSX/Windows, and does not use any Lua language features beyond Lua 5.1, so should be compatible with most Lua environments (including LuaJIT).

Simple Example
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

For more complex examples (eg. channels) please see the [lusc_luv tests here](https://github.com/svermeulen/lusc_luv/blob/main/gen/lusc_luv/tests/lusc_spec.lua).  If you're able to read through each of those tests, and understand what's going on, then you're in great shape to use Lusc in your own projects.

Running the examples
---

You might notice that in the examples above, we are not calling the `main()` functions directly.  This is because, similar to trio, all `lusc.X` methods need to be executed underneath a `lusc.run` function.  However, unlike Trio, in order to call `lusc.run`, the user has to supply implementations for `sleep` and `get_time`. This is necessary since this functionality varies depending on the environment where you are running Lua.

`lusc.run` takes a `time_provider` that should be a function that return the current time in seconds (which doesn't have to be the actual time, but just a time value that starts from some arbitrary point in the past) and also a `sleep_handler` function that performs a sleep with a given number of seconds.

If running in a Linux/OSX environment a simple way to achieve this would be the following (which you can execute for yourself by running the lua files in the `examples/` folder):

```lua
-- NOTE: Do not use this function in a real app

local function run(entry_point)
   lusc.run({
      entry_point = entry_point,
      time_provider = function()
         return os.time()
      end,
      sleep_handler = function(seconds)
         os.execute("sleep " .. tostring(seconds))
      end,
   })
end

run(main)
```

However - This approach has many limitations:
* `os.time()` does not provide sub-second precision
* `os.execute("sleep x")` is not cross platform (windows would require a different command)
* Using `os.execute` for sleep is a fairly heavy operation

Instead, you should use lusc on top of something else that can provide better implementations for sleep() and get_time().

For example, if you are ok with adding a dependency to [Luv](https://github.com/luvit/luv) you can use [lusc_luv](https://github.com/svermeulen/lusc_luv) instead

API Reference
---

```lua

-- NOTE - The code here is not valid Lua code - it is Teal code, which gets
-- compiled to Lua
-- But can be used as reference for your lua code to understand the API and the methods/types
local record lusc
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

      parent: Task
   end

   record Event
      is_set:boolean

      set:function(Event)
      await:function(Event)
   end

   record CancelledError
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

      cancel_scope: CancelScope

      -- TODO
      -- start:function()

      start_soon:function(self: Nursery, func:function(), Task.Opts)
   end

   open_nursery:function(handler:function(nursery:Nursery), opts:Nursery.Opts):CancelScope.Result
   get_time:function():number
   await_sleep:function(seconds:number)
   await_until:function(until_time:number)
   await_forever:function()
   new_event:function():Event
   run:function(opts:Opts)

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

   has_started:function():boolean

   get_root_nursery:function():Nursery

   cancel_all:function()
   open_channel:function<T>(max_buffer_size:integer):Channel<T>

   get_running_task:function():Task
   try_get_running_task:function():Task
end
```

More Examples / Docs
---

For further documentation/examples we recommend looking at "lusc_spec.tl" in this repo, which covers all the features of lusc.  You can run these tests using busted library by executing the script at `scripts/run_tests.sh`

Strong Typing Support
---

Note that this library is implemented using [Teal](https://github.com/teal-language/tl) and that all the lua files here are generated.  If you are also using Teal, and want your calls to the lusc API strongly typed, you can copy and paste the teal type definition files from `/dist/lusc.d.tl` into your project (or just add a path directly to the source code here in your tlconfig.lua file)

History / Credits
---

This library is based on [this great series](https://gist.github.com/belm0/4c6d11f47ccd31a231cde04616d6bb22) of articles explaining how to add structured concurrency support to Lua by @belm0.  One difference with the implementation provided in the article is that this library is compatible with Lua 5.1 (since it does not use to-be-closed variables).  This was necessary to provide LuaJIT compatibility.

