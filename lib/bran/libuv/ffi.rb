
require 'ffi'

module Bran
  module LibUV
    module FFI
      extend ::FFI::Library
      
      libfile = "libuv.#{::FFI::Platform::LIBSUFFIX}"
      
      ffi_lib \
        File.expand_path("../../../ext/libuv/#{libfile}", File.dirname(__FILE__))
      
      opts = {
        blocking: true  # only necessary on MRI to deal with the GIL.
      }
      
      UV_READABLE = 1
      UV_WRITABLE = 2
      
      # Struct sizes/allocators
      %w(uv_loop uv_poll uv_signal uv_timer).each do |type|
        eval <<-RUBY
          typedef :pointer, :#{type}_ptr
          attach_function :#{type}_sizeof, [], :size_t, **opts
          #{type.upcase}_SIZEOF = #{type}_sizeof
          
          def self.#{type}_alloc
            ptr = ::FFI::MemoryPointer.new(#{type.upcase}_SIZEOF)
            ptr.autorelease = false
            ptr
          end
        RUBY
      end
      
      typedef :int, :uv_os_sock_t # not true on Windows, but we don't care
      
      typedef enum([
        :default,
        :once,
        :nowait
      ]), :uv_run_mode
      
      ##
      # Callback factory methods.
      #
      # WARNING: If your Ruby code doesn't retain a reference to the
      #   FFI::Function object after passing it to a C function call,
      #   it may be garbage collected while C still holds the pointer,
      #   potentially resulting in a segmentation fault.
      
      typedef :pointer, :uv_poll_cb_ptr
      def self.uv_poll_cb(&block)
        #        (handle,   status, events)
        params = [:pointer, :int,   :int]
        ::FFI::Function.new :void, params, blocking: true do |*args|
          block.call(*args)
        end
      end
      
      typedef :pointer, :uv_signal_cb_ptr
      def self.uv_signal_cb(&block)
        #        (handle,   signo)
        params = [:pointer, :int]
        ::FFI::Function.new :void, params, blocking: true do |*args|
          block.call(*args)
        end
      end
      
      typedef :pointer, :uv_timer_cb_ptr
      def self.uv_timer_cb(&block)
        #        (handle)
        params = [:pointer]
        ::FFI::Function.new :void, params, blocking: true do |*args|
          block.call(*args)
        end
      end
      
      attach_function :uv_strerror, [:int], :string, **opts
      attach_function :uv_err_name, [:int], :string, **opts
      
      attach_function :uv_loop_init, [:uv_loop_ptr], :int, **opts
      attach_function :uv_loop_close, [:uv_loop_ptr], :int, **opts
      attach_function :uv_loop_alive, [:uv_loop_ptr], :int, **opts
      
      attach_function :uv_run, [:uv_loop_ptr, :uv_run_mode], :int, **opts
      attach_function :uv_stop, [:uv_loop_ptr], :void, **opts
      
      attach_function :uv_poll_init, [:uv_loop_ptr, :uv_poll_ptr, :int], :int, **opts
      attach_function :uv_poll_init_socket, [:uv_loop_ptr, :uv_poll_ptr, :uv_os_sock_t], :int, **opts
      attach_function :uv_poll_start, [:uv_poll_ptr, :int, :uv_poll_cb_ptr], :int, **opts
      attach_function :uv_poll_stop, [:uv_poll_ptr], :int, **opts
      
      attach_function :uv_signal_init, [:uv_loop_ptr, :uv_signal_ptr], :int, **opts
      attach_function :uv_signal_start, [:uv_signal_ptr, :uv_signal_cb_ptr, :int], :int, **opts
      attach_function :uv_signal_stop, [:uv_signal_ptr], :int, **opts
      
      attach_function :uv_timer_init, [:uv_loop_ptr, :uv_timer_ptr], :int, **opts
      attach_function :uv_timer_start, [:uv_timer_ptr, :uv_timer_cb_ptr, :uint64, :uint64], :int, **opts
      attach_function :uv_timer_stop, [:uv_timer_ptr], :int, **opts
    end
  end
end
