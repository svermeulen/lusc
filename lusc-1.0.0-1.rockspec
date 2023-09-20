rockspec_format = "3.0"
package = "lusc"
version = "1.0.0-1"
source = {
   url = "git+https://github.com/svermeulen/lusc.git",
   branch = "main"
}
description = {
   summary = "Structured Concurrency support for Lua",
   detailed = "Structured Concurrency support for Lua",
   homepage = "https://github.com/svermeulen/lusc",
   license = "MIT"
}
dependencies = {
   "lua >= 5.1",
}
build = {
   type = "builtin",
   modules = {
      lusc = "gen/lusc/init.tl"
   },
}
