
require("busted")

local lusc <const> = require('lusc')
local util <const> = require('lusc.util')

describe("lusc util", function()
   it("util.is_instance", function()
      local group = lusc.ErrorGroup.new({})
      util.assert(util.is_instance(group, lusc.ErrorGroup))
      util.assert(not util.is_instance(group, lusc.Task))
   end)
end)
