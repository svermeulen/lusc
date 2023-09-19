
local lusc <const> = require('lusc')

lusc.set_log_handler(function(message:string)
   print(message)
end)

