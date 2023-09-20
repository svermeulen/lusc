local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local pcall = _tl_compat and _tl_compat.pcall or pcall; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local xpcall = _tl_compat and _tl_compat.xpcall or xpcall
local util = {TryOpts = {}, }







local _log_handler = nil

function util.is_log_enabled()
   return _log_handler ~= nil
end

function util.log(format, ...)
   if util.is_log_enabled() then
      _log_handler(string.format(format, ...))
   end
end

function util.set_log_handler(log_handler)
   _log_handler = log_handler
end

function util.map_is_empty(values)
   for _, _ in pairs(values) do
      return false
   end

   return true
end

function util.binary_search(items, item, comparator)
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

function util.assert(condition, format, ...)
   if not condition then
      error(string.format(format, ...))
   end
end

function util.is_instance(obj, cls)

   return getmetatable(obj).__index == cls
end

function util.index_of(list, item)
   for i = 1, #list do
      if item == list[i] then
         return i
      end
   end

   return -1
end

function util.remove_element(list, item)
   local index = util.index_of(list, item)
   util.assert(index ~= -1, "Attempted to remove item from array that does not exist in array")
   table.remove(list, index)
end

function util.clear_table(values)
   for k, _ in pairs(values) do
      values[k] = nil
   end
end

function util.partial_func1(action, p1)
   return function()
      return action(p1)
   end
end

local function _on_error(error_obj)
   return debug.traceback(error_obj, 2)
end

function util.try(t)
   local success, ret_value = xpcall(t.action, _on_error)
   if success then
      if t.finally then
         t.finally()
      end
      return ret_value
   end
   if not t.catch then
      if t.finally then
         t.finally()
      end
      error(ret_value, 2)
   end
   success, ret_value = xpcall((function()
      return t.catch(ret_value)
   end), _on_error)
   if t.finally then
      t.finally()
   end
   if success then
      return ret_value
   end
   return error(ret_value, 2)
end

function util.assert_throws(action)
   local ok = pcall(action)
   if ok then
      error("Expected exception when calling given function but no error was found!")
   end
end

function util.shallow_clone(source)
   if type(source) == "table" then
      local copy = {}
      for orig_key, orig_value in pairs(source) do
         copy[orig_key] = orig_value
      end
      return copy
   end


   return source
end

return util
