
module Bran
  module LibUV
    class Reactor
      module Collections
        
        class Abstract
          def initialize(reactor)
            @reactor = reactor
            
            @idents_by_addr  = {}
            @items_by_ident  = {}
            @stacks_by_ident = {}
          end
          
          def push(ident, handler, persistent)
            if (stack = @stacks_by_ident[ident])
              stack << [handler, persistent]
            else
              item = make_item(ident)
              
              @items_by_ident[ident]        = item
              @idents_by_addr[item.address] = ident
              @stacks_by_ident[ident]       = [[handler, persistent]]
            end
            
            ident
          end
          
          def pop(ident)
            stack = @stacks_by_ident[ident]
            return unless stack
            
            stack.pop
            return unless stack.empty?
            
            @stacks_by_ident.delete(ident)
            item = @items_by_ident.delete(ident)
            @idents_by_addr.delete(item.address)
            
            drop_item(ident, item)
          end
          
          def item_by_ident(ident)
            @items_by_ident[ident]
          end
          
          def invoke_by_ident(ident, rc = 0)
            stack = @stacks_by_ident[ident]
            return unless ident
            
            handler, persistent = stack.last
            pop ident unless persistent
            
            invoke_handler(handler, rc)
          end
          
          def invoke_by_addr(addr, rc = 0)
            ident = @idents_by_addr[addr]
            return unless ident
            
            stack = @stacks_by_ident.fetch(ident)
            
            handler, persistent = stack.last
            pop ident unless persistent
            
            invoke_handler(handler, rc)
          end
          
          def invoke_handler(handler, rc = 0)
            case handler
            when ::Fiber
              if rc == 0
                handler.resume nil
              else
                handler.resume Util.error_create("running the libuv loop", rc)
              end
            when ::Proc
              if rc == 0
                handler.call nil
              else
                error = Util.error_create("running the libuv loop", rc)
                handler.call error
              end
            end
          end
          
          def make_item(ident)
            item = concrete_alloc_item
            concrete_start_item(ident, item)
            
            item
          end
          
          def drop_item(ident, item)
            concrete_stop_item(ident, item)
            concrete_release_item(item)
            
            nil
          end
        end
        
        class AbstractSister < Abstract
          attr_accessor :sister
          attr_accessor :item_pool
          
          def bond_with(sister)
            @sister = sister
            @item_pool = []
            
            @sister.sister = self
            @sister.item_pool = @item_pool
          end
          
          def make_item(ident)
            item = @sister.item_by_ident(ident)
            return super unless item
            
            @sister.concrete_sister_share_item(ident, item)
            
            item
          end
          
          def drop_item(ident, item)
            sister_item = @sister.item_by_ident(ident)
            return super unless sister_item == item
            
            @sister.concrete_sister_unshare_item(ident, item)
            
            nil
          end
        end
        
        class Read < AbstractSister
          def initialize(*)
            super
            @callback    = FFI.uv_poll_cb(&@reactor.method(:_read_callback))
            @rw_callback = FFI.uv_poll_cb(&@reactor.method(:_rw_callback))
          end
          
          def concrete_alloc_item
            @item_pool.pop || FFI.uv_poll_alloc
          end
          
          def concrete_release_item(item)
            @item_pool << item
          end
          
          def concrete_start_item(ident, item)
            Util.error_check "creating the poll readable item",
              FFI.uv_poll_init(@reactor.ptr, item, ident)
            
            Util.error_check "starting the poll readable item",
              FFI.uv_poll_start(item, FFI::UV_READABLE, @callback)
          end
          
          def concrete_stop_item(ident, item)
            Util.error_check "stopping the poll readable item",
              FFI.uv_poll_stop(item)
          end
          
          def concrete_sister_share_item(ident, item)
            Util.error_check "starting the poll readable + writable item",
              FFI.uv_poll_start(item,
                FFI::UV_READABLE | FFI::UV_WRITABLE, @rw_callback)
          end
          
          def concrete_sister_unshare_item(ident, item)
            Util.error_check "restarting the poll readable item",
              FFI.uv_poll_start(item, FFI::UV_READABLE, @callback)
          end
        end
        
        class Write < AbstractSister
          def initialize(*)
            super
            @callback    = FFI.uv_poll_cb(&@reactor.method(:_write_callback))
            @rw_callback = FFI.uv_poll_cb(&@reactor.method(:_rw_callback))
          end
          
          def concrete_alloc_item
            @item_pool.pop || FFI.uv_poll_alloc
          end
          
          def concrete_release_item(item)
            @item_pool << item
          end
          
          def concrete_start_item(ident, item)
            Util.error_check "creating the poll writable item",
              FFI.uv_poll_init(@reactor.ptr, item, ident)
            
            Util.error_check "starting the poll writable item",
              FFI.uv_poll_start(item, FFI::UV_WRITABLE, @callback)
          end
          
          def concrete_stop_item(ident, item)
            Util.error_check "stopping the poll writable item",
              FFI.uv_poll_stop(item)
          end
          
          def concrete_sister_share_item(ident, item)
            Util.error_check "starting the poll writable + writable item",
              FFI.uv_poll_start(item,
                FFI::UV_READABLE | FFI::UV_WRITABLE, @rw_callback)
          end
          
          def concrete_sister_unshare_item(ident, item)
            Util.error_check "restarting the poll writable item",
              FFI.uv_poll_start(item, FFI::UV_WRITABLE, @callback)
          end
        end
        
        class Signal < Abstract
          def initialize(*)
            super
            @item_pool = []
            @callback  = FFI.uv_signal_cb(&@reactor.method(:_signal_callback))
          end
          
          def concrete_alloc_item
            @item_pool.pop || FFI.uv_signal_alloc
          end
          
          def concrete_release_item(item)
            @item_pool << item
          end
          
          def concrete_start_item(ident, item)
            Util.error_check "creating the signal handler item",
              FFI.uv_signal_init(@reactor.ptr, item)
            
            Util.error_check "starting the signal handler item",
              FFI.uv_signal_start(item, @callback, ident)
          end
          
          def concrete_stop_item(ident, item)
            Util.error_check "stopping the signal handler item",
              FFI.uv_signal_stop(item)
          end
        end
        
      end
    end
  end
end