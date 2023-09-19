
local Try <const> = require("lusc.util.try")

local record util
end

local _log_handler:function(string) = nil

function util.is_log_enabled():boolean
   return _log_handler ~= nil
end

function util.log(format:string, ...:any)
   if util.is_log_enabled() then
      _log_handler(string.format(format, ...))
   end
end

function util.set_log_handler(log_handler:function(string))
   _log_handler = log_handler
end

function util.map_is_empty<K, V>(values:{K:V}):boolean
   for _, _ in pairs(values) do
      return false
   end

   return true
end

function util.binary_search<T>(items:{T}, item:T, comparator:function(T, T):integer):integer
   local low = 1
   local high = #items

   while low <= high do
      local mid = math.floor((low + high) / 2)
      local candidate = items[mid]
      local cmp = comparator(candidate, item)

      if cmp == 0 then
         return mid
      elseif cmp > 0 then
         low = mid + 1
      else
         high = mid - 1
      end
   end
   return low
end

function util.assert(condition:boolean, format:string, ...:any)
   if not condition then
      error(string.format(format, ...))
   end
end

function util.is_instance(obj:any, cls:any):boolean
   -- We use a simple class model by convention where class is __index
   return getmetatable(obj).__index == cls
end

function util.index_of<T>(list:{T}, item:T):integer
   for i=1,#list do
      if item == list[i] then
         return i
      end
   end

   return -1
end

function util.remove_element<T>(list:{T}, item:T)
   local index = util.index_of(list, item)
   util.assert(index ~= -1, "Attempted to remove item from array that does not exist in array")
   table.remove(list, index)
end

function util.clear_table<K, V>(values:{K:V})
   for k, _ in pairs(values) do
      values[k] = nil
   end
end

function util.partial_func1<P1, TReturn>(action:(function(P1):TReturn), p1:P1):(function():TReturn)
   return function():TReturn
      return action(p1)
   end
end

function util.try<T>(opts:Try.Opts<T>):T
   return Try(opts)
end

function util.throws(action:function())
   local ok = pcall(action)
   if ok then
      error("Expected exception when calling given function but no error was found!")
   end
end

function util.shallow_clone<T>(source:T):T
   if source is table then
      local copy = {}
      for orig_key, orig_value in pairs(source) do
         copy[orig_key] = orig_value
      end
      return copy as T
   end

   -- number, string, boolean, etc
   return source
end

return util
