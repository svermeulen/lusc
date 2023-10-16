
local util <const> = require('lusc.internal.util')

util.set_log_handler(function(message:string)
   print(message)
end)

