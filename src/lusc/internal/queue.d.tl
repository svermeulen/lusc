
local record Queue<T>
   count:integer
   enqueue:function(Queue<T>, value:T)
   dequeue:function(Queue<T>):T
   iterate:function(Queue<T>):function():integer, T
   empty:function(Queue<T>):boolean
   peek:function(Queue<T>):T
   contains:function(Queue<T>, item:T):boolean
   clear:function()

   --- Returns the amount of items that were removed
   remove_value:function(Queue<T>, value:T):integer

   metamethod __call: function(self: Queue<T>): Queue<T>
end

return Queue
