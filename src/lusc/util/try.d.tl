
local record Try
   record Opts<T>
      action:function():T
      catch:function(err:any):T
      finally:function()
   end

   metamethod __call: function<T>(self: Try, Opts<T>):T
end

return Try
