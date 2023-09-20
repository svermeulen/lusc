
require("busted")

local lusc = require('lusc')
local util = require('lusc.util')

describe("lusc util", function()
   it("util.is_instance", function()
      util.log("yoooo")
      local group = lusc.ErrorGroup.new({})
      util.assert(util.is_instance(group, lusc.ErrorGroup))
      util.assert(not util.is_instance(group, lusc.Task))
   end)
end)
