
::Bran::Ext.assume do
  check ::Ethon::Multi < ::Ethon::Multi::Operations
  check ::Ethon::Multi::Operations.instance_method(:handle).arity == 0
  check ::Ethon::Multi::Operations.instance_method(:check).arity == 0
  
  check ::Ethon::Multi < ::Ethon::Multi::Stack
  check ::Ethon::Multi::Stack.instance_method(:easy_handles).arity == 0
  
  check ::Ethon::Multi < ::Ethon::Multi::Options
  check ::Ethon::Multi::Options.instance_method(:socketfunction=).arity == 1
  check ::Ethon::Multi::Options.instance_method(:timerfunction=).arity == 1
  
  check ::Ethon::Errors::MultiTimeout.instance_method(:initialize).arity == 1
  
  check ::Ethon::Curl.method(:multi_socket_action)
  check ::Ethon::Curl::POLL_IN
  check ::Ethon::Curl::POLL_OUT
  check ::Ethon::Curl::POLL_INOUT
  check ::Ethon::Curl::POLL_REMOVE
  check ::Ethon::Curl::SOCKET_TIMEOUT
  check ::Ethon::Curl::CSELECT_IN
  check ::Ethon::Curl::CSELECT_OUT
end

module Ethon
  
  class Multi
    class Bran
      def initialize(fm, multi)
        @fm    = fm
        @multi = multi
        
        @multi.socketfunction = method(:_socketfunction_callback).to_proc
        @multi.timerfunction  = method(:_timerfunction_callback).to_proc
      end
      
      def perform
        fm = Thread.current.thread_variable_get(:fiber_manager)
        return unless fm == @fm # abort if not run within the same context.
        
        @curl_readables = {}
        @curl_writables = {}
        @fds_remaining_ptr = ::FFI::MemoryPointer.new(:int)
        
        raise @callback_error if @callback_error
        
        @perform_fiber = ::Fiber.current
        ::Fiber.yield
        @perform_fiber = nil
        
        raise @callback_error if @callback_error
        
        true
      end
      
    private
      
      def _socketfunction_callback(easy_handle, fd, action, *)
        case action
        when ::Ethon::Curl::POLL_IN     then poll_in(fd)
        when ::Ethon::Curl::POLL_OUT    then poll_out(fd)
        when ::Ethon::Curl::POLL_INOUT  then poll_in(fd); poll_out(fd)
        when ::Ethon::Curl::POLL_REMOVE then poll_remove(fd)
        end
        
        0
      rescue Exception => e
        @callback_error = e
        @fm.resume_soon(@perform_fiber) if @perform_fiber
        
        0
      end
      
      def _timerfunction_callback(_, timeout_ms, *)
        timer_cancel
        
        return if timeout_ms.is_a?(::Bignum) # corresponds to -1
        
        @timeout_timer = @fm.loop.timer_oneshot timeout_ms / 1000.0 do
          @timeout_timer = nil
          
          socket_action!(::Ethon::Curl::SOCKET_TIMEOUT, 0) if @perform_fiber
        end
        
        0
      rescue Exception => e
        @callback_error = e
        @fm.resume_soon(@perform_fiber) if @perform_fiber
        
        0
      end
      
      def poll_in(fd)
        return if @curl_readables[fd]
        @curl_readables[fd] = true
        
        @fm.loop.push_readable fd,
          Proc.new { socket_action!(fd, ::Ethon::Curl::CSELECT_IN) }
      end
      
      def poll_out(fd)
        return if @curl_writables[fd]
        @curl_writables[fd] = true
        
        @fm.loop.push_writable fd,
          Proc.new { socket_action!(fd, ::Ethon::Curl::CSELECT_OUT) }
      end
      
      def poll_remove(fd)
        @fm.loop.pop_readable(fd) if @curl_readables.delete(fd)
        @fm.loop.pop_writable(fd) if @curl_writables.delete(fd)
        
        maybe_finish!
      end
      
      def timer_cancel
        @fm.loop.timer_cancel @timeout_timer if @timeout_timer
      end
      
      def socket_action!(fd, flags)
        code = ::Ethon::Curl.multi_socket_action(@multi.handle, fd, flags,
                                                 @fds_remaining_ptr)
        raise ::Ethon::Errors::MultiTimeout.new(code) unless code == :ok
        
        if @fds_remaining_ptr.read_int == 0
          @multi.__send__(:check)
          maybe_finish!
        end
      end
      
      def maybe_finish!
        return unless @curl_readables.empty? && @curl_writables.empty? \
                                             && @multi.easy_handles.empty?
        timer_cancel
        
        @perform_fiber.resume
      end
      
    end
  end
end
