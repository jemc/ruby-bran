
module Bran
  module LibUV
    class Reactor
      
      # Raised when an operation is performed on an already-destroyed Loop.
      class DestroyedError < RuntimeError; end
      
      def initialize
        @ptr = FFI.uv_loop_alloc
        Util.error_check "creating the loop",
          FFI.uv_loop_init(@ptr)
        
        @finalizer = self.class.create_finalizer_for(@ptr)
        ObjectSpace.define_finalizer(self, @finalizer)
        
        @available_polls     = []
        @running_reads       = {}
        @running_writes      = {}
        @fds_by_read_addr    = {}
        @fds_by_write_addr   = {}
        @on_readables        = {}
        @on_writables        = {}
        
        @available_signals   = []
        @running_signals     = {}
        
        @available_timers    = []
        @running_timers      = {}
        
        @poll_read_callback  = FFI.uv_poll_cb(&method(:_poll_read_callback))
        @poll_write_callback = FFI.uv_poll_cb(&method(:_poll_write_callback))
        @poll_rw_callback    = FFI.uv_poll_cb(&method(:_poll_rw_callback))
        
        # TODO: add more Ruby-compatible signal handlers by default?
        signal_start(:INT) { @abort_signal = :INT; stop! }
      end
      
      # Free the native resources associated with this object. This will
      # be done automatically on garbage collection if not called explicitly.
      def destroy
        if @finalizer
          @finalizer.call
          ObjectSpace.undefine_finalizer(self)
        end
        @ptr = @finalizer = nil
        
        @available_polls      = \
          @running_reads      = @running_writes      = \
          @fds_by_read_addr   = @fds_by_write_addr   = \
          @on_readables       = @on_writables        = \
          @available_signals  = @running_signals     = \
          @available_timers   = @running_timers      = \
          @poll_read_callback = @poll_write_callback = nil
        
        self
      end
      
      # @api private
      def ptr
        raise DestroyedError unless @ptr
        @ptr
      end
      
      # @api private
      def self.create_finalizer_for(ptr)
        Proc.new do
          FFI.uv_loop_close(ptr)
          # TODO: prevent running finalizer when loop hasn't been stopped?
          ptr.free
        end
      end
      
      # Capture exceptions raised from callbacks, stopping the loop,
      # capturing the exception to be re-raised outside the loop in #run!.
      # @api private
      def rescue_abort
        yield
      rescue Exception => ex
        @abort_exception = ex
        stop!
      end
      
      # Run the libuv event loop in default (blocking) mode,
      # running until stopped or until all handles are removed.
      def run!
        @abort_exception = nil
        @abort_signal = nil
        
        rc = FFI.uv_run(ptr, :default)
        
        # If an exception or signal caused the stop, re-raise it here.
        raise @abort_exception if @abort_exception
        Process.kill(@abort_signal, Process.pid) if @abort_signal
        
        Util.error_check "running the loop in blocking mode", rc
      end
      
      # Return true if there are active handles or request in the loop.
      def stop!
        FFI.uv_stop(ptr)
      end
      
      # Push the given handler for the given fd, adding if necessary.
      # If persistent is false, the handler will be popped after one trigger.
      def push_readable(fd, handler, persistent = true)
        ptr  = ptr()
        fd   = Integer(fd)
        poll = nil
        
        if (readables = @on_readables[fd])
          readables << [handler, persistent]
        elsif (poll = @running_writes[fd])
          @running_reads[fd]              = poll
          @fds_by_read_addr[poll.address] = fd
          @on_readables[fd]               = [[handler, persistent]]
          
          Util.error_check "starting the poll readable + writable entry",
            FFI.uv_poll_start(poll, FFI::UV_READABLE | FFI::UV_WRITABLE, @poll_rw_callback)
        else
          poll = @available_polls.pop || FFI.uv_poll_alloc
          @running_reads[fd]              = poll
          @fds_by_read_addr[poll.address] = fd
          @on_readables[fd]               = [[handler, persistent]]
          
          # TODO: investigate if need not init existing available_polls.
          Util.error_check "creating the poll readable entry",
            FFI.uv_poll_init(ptr, poll, fd)
          
          Util.error_check "starting the poll readable entry",
            FFI.uv_poll_start(poll, FFI::UV_READABLE, @poll_read_callback)
        end
        
        fd
      end
      
      # Push the given handler for the given fd, adding if necessary.
      # If persistent is false, the handler will be popped after one trigger.
      def push_writable(fd, handler, persistent = true)
        ptr  = ptr()
        fd   = Integer(fd)
        poll = nil
        
        if (writables = @on_writables[fd])
          writables << [handler, persistent]
        elsif (poll = @running_reads[fd])
          @running_writes[fd]              = poll
          @fds_by_write_addr[poll.address] = fd
          @on_writables[fd]                = [[handler, persistent]]
          
          Util.error_check "starting the poll readable + writable entry",
            FFI.uv_poll_start(poll, FFI::UV_READABLE | FFI::UV_WRITABLE, @poll_rw_callback)
        else
          poll = @available_polls.pop || FFI.uv_poll_alloc
          @running_writes[fd]              = poll
          @fds_by_write_addr[poll.address] = fd
          @on_writables[fd]                = [[handler, persistent]]
          
          # TODO: investigate if need not init existing available_polls.
          Util.error_check "creating the poll writeable entry",
            FFI.uv_poll_init(ptr, poll, fd)
          
          Util.error_check "starting the poll writeable entry",
            FFI.uv_poll_start(poll, FFI::UV_WRITABLE, @poll_write_callback)
        end
        
        fd
      end
      
      # Remove the next readable handler for the given fd.
      def pop_readable(fd)
        fd = Integer(fd)
        
        readables = @on_readables[fd]
        return unless readables
        
        readables.pop
        return unless readables.empty?
        
        @on_readables.delete(fd)
        poll = @running_reads.delete(fd)
        @fds_by_read_addr.delete(poll.address)
        
        Util.error_check "stopping the poll readable entry",
          FFI.uv_poll_stop(poll)
        
        if poll == @running_writes[fd]
          Util.error_check "restarting the poll writable entry",
            FFI.uv_poll_start(poll, FFI::UV_WRITABLE, @poll_write_callback)
          
          return
        end
        
        @available_polls << poll
        
        nil
      end
      
      # Remove the next writable handler for the given fd.
      def pop_writable(fd)
        fd = Integer(fd)
        
        writables = @on_writables[fd]
        return unless writables
          
        writables.pop
        return unless writables.empty?
        
        @on_writables.delete(fd)
        poll = @running_writes.delete(fd)
        @fds_by_write_addr.delete(poll.address)
        
        Util.error_check "stopping the poll writable entry",
          FFI.uv_poll_stop(poll)
        
        if poll == @running_reads[fd]
          Util.error_check "restarting the poll readable entry",
            FFI.uv_poll_start(poll, FFI::UV_READABLE, @poll_read_callback)
          
          return
        end
        
        @available_polls << poll
        
        nil
      end
      
      # Start handling the given signal, running the given block when it occurs.
      def signal_start(signo, &block)
        ptr   = ptr()
        signo = Signal.list.fetch(signo.to_s) unless signo.is_a?(Integer)
        
        signal_stop(signo) if @running_signals.has_key?(signo)
        
        callback = FFI.uv_signal_cb do |_, _|
          rescue_abort do
            block.call self, signo
          end
        end
        
        signal = @available_signals.pop || FFI.uv_signal_alloc
        @running_signals[signo] = [signal, callback]
        
        # TODO: investigate if need not init existing available_signals
        Util.error_check "creating the signal item",
          FFI.uv_signal_init(ptr, signal)
        
        Util.error_check "starting the signal item",
          FFI.uv_signal_start(signal, callback, signo)
      end
      
      # Stop handling the given signal.
      def signal_stop(signo)
        signo = Signal.list.fetch(signo.to_s) unless signo.is_a?(Integer)
        
        signal, callback = @running_signals.delete(signo)
        
        return unless signal
        
        Util.error_check "stopping the signal item",
          FFI.uv_signal_stop(signal)
        
        @available_signals << signal
        
        nil
      end
      
      # Start a timer to run the given block after the given timeout.
      # If a repeat_interval is given, after the first run, the block will be
      # run repeatedly at that interval. If a repeat_interval is not given,
      # or given as nil or 0, timer_cancel is called automatically at first run.
      # Both timeout and repeat_interval should be given in seconds.
      def timer_start(timeout, repeat_interval = nil, &block)
        ptr = ptr()
        
        timeout = (timeout * 1000).ceil
        
        repeat = false
        if repeat_interval and repeat_interval > 0
          repeat_interval = (repeat_interval * 1000).ceil
          repeat          = true
        else
          repeat_interval = 0
        end
        
        raise ArgumentError, "callback block required" unless block
        
        timer = @available_timers.pop || FFI.uv_timer_alloc
        id    = timer.address
        
        callback = FFI.uv_timer_cb do |_|
          rescue_abort do
            block.call self, id
            
            timer_cancel(id) unless repeat
          end
        end
        
        @running_timers[id] = [timer, callback]
        
        # TODO: investigate if need not init existing available_timers
        Util.error_check "creating the timer item",
          FFI.uv_timer_init(ptr, timer)
        
        Util.error_check "starting the timer item",
          FFI.uv_timer_start(timer, callback, timeout, repeat_interval)
        
        id
      end
      
      # Stop handling the given timer.
      def timer_cancel(id)
        id = Integer(id)
        
        timer, callback = @running_timers.delete(id)
        
        return unless timer
        
        Util.error_check "stopping the timer item",
          FFI.uv_timer_stop(timer)
        
        @available_timers << timer
        
        nil
      end
      
      # Start a timer to run the given block after the given timeout.
      # The timer will be run just once, starting now.
      def timer_oneshot(time, &block)
        timer_start(time, &block)
      end
      
      # Start a timer to wake the given fiber after the given timeout.
      # The timer will be run just once, starting now.
      def timer_oneshot_wake(time, fiber)
        timer_start(time) { fiber.resume } # TODO: optimize this case
      end
      
    private
      
      # Callback method called directly from FFI when an event is readable.
      def _poll_read_callback(poll, rc, events)
        rescue_abort do
          fd        = @fds_by_read_addr.fetch(poll.address)
          readables = @on_readables.fetch(fd)
          
          handler, persistent = readables.last
          pop_readable(fd) unless persistent
          
          invoke_handler(handler, rc)
        end
      end
      
      # Callback method called directly from FFI when an event is writable.
      def _poll_write_callback(poll, rc, events)
        rescue_abort do
          fd        = @fds_by_write_addr.fetch(poll.address)
          writables = @on_writables.fetch(fd)
          
          handler, persistent = writables.last
          pop_writable(fd) unless persistent
          
          invoke_handler(handler, rc)
        end
      end
      
      # Callback method called directly from FFI when an event is readable or writable.
      def _poll_rw_callback(poll, rc, events)
        _poll_read_callback(poll, rc, events)  if events & FFI::UV_READABLE != 0
        _poll_write_callback(poll, rc, events) if events & FFI::UV_WRITABLE != 0
      end
      
      # Invoke the given handler, possibly converting the given rc to an error.
      def invoke_handler(handler, rc)
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
      
    end
  end
end
