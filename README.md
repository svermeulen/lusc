
Lusc - Structured Async/Concurrency for Lua
-----

This library brings the concepts of [Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) to Lua.  The name is an abbrevriation of this (**LU**a **S**tructured **C**oncurrency).

This programming paradigm was first popularized by the python library [Trio](https://github.com/python-trio/trio) and this library basically mirrors that API in Lua.  So if you are already familiar with Trio then you should be able to immediately understand the Lusc API.

If you aren't familiar with Trio, and also aren't familiar with [Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency), then it might be a good idea to read the [trio docs](https://trio.readthedocs.io/en/stable/reference-core.html) since they are much better than what you'll read here.

Simple Examples
---

Run multiple tasks in parallel:

```
local lusc = require("lusc")

local function main()
   print("Waiting 1 second...")
   lusc.await_sleep(1)

   print("Creating child tasks...")

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

   print("Completed all child tasks")
end
```

API Reference
---


Luv Bindings
---

You might notice that in the examples above, we are not calling the `main()` functions directly.  This is because, similar to trio, these all need to be executed underneath a `lusc.run` function.  However, unlike Trio, in order to call this function, the user has to supply implementations for `sleep` and `get_time` functions, since these vary depending on the environment where you are running Lua.

Therefore `lusc.run` returns a coroutine that yields with the number of seconds to sleep, and so the calling code needs to handle that.

If running in a Linux/OSX environment a simple way to achieve this would be this:

```

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

# Strong Typing Support

Note that this library is implemented using [Teal](https://github.com/teal-language/tl) and that all the lua files here are generated.  If you are also using Teal, and want your calls to the text-to-colorscheme API strongly typed, you can copy and paste the teal type definition files from `/dist/lusc.d.tl` into your project (or just add a path directly to the source code here in your tlconfig.lua file)

History / Credits
---

This library is based on [this great series](https://gist.github.com/belm0/4c6d11f47ccd31a231cde04616d6bb22) of articles explaining how to add structured concurrency support to Lua by @belm0.  One difference with the implementation provided in the article is that this library is compatible with Lua 5.1 (since it does not use to-be-closed variables).  This was necessary to provide LuaJIT compatibility.

