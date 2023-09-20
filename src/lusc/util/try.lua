local _on_error
_on_error = function(error_obj)
  return debug.traceback(error_obj, 2)
end
return function(t)
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
