rockspec_format = "3.0"
package = "lusc"
version = "1.0.0-2"
source = {
   url = "git+https://github.com/svermeulen/lusc.git",
   branch = "main"
}
description = {
   summary = "Structured Concurrency support for Lua for easy management of async tasks",
   detailed = "Structured Concurrency support for Lua for easy management of async tasks",
   homepage = "https://github.com/svermeulen/lusc",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
}
build = {
   type = "builtin",
   modules = {
      lusc = "gen/lusc/init.lua",
      ["lusc.util"] = "gen/lusc/util.lua"
   },
}
