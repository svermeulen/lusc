
Lusc - Structured Async/Concurrency for Lua
-----

This library brings the concepts of [Structured Concurrency](https://en.wikipedia.org/wiki/Structured_concurrency) to Lua.  The name is an abbrevriation of this (**LU**a **S**tructured **C**oncurrency).

This programming paradigm was first popularized by the python library [Trio](https://github.com/python-trio/trio) and this library basically mirrors that API except for Lua instead.  So if you are already familiar with Trio then you should be able to immediately understand the Lusc API.

Examples
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

History
---

This library is based on [this great series](https://gist.github.com/belm0/4c6d11f47ccd31a231cde04616d6bb22) of articles explaining how to add structured concurrency support to Lua.  One difference with the implementation provided in the article is that this library is compatible with Lua 5.1 (since it does not use to-be-closed variables).  This was necessary to provide LuaJIT compatibility.

