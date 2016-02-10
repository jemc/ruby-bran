
require_relative "reactor/collections"

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
        
        @read_polls  = Collections::Read.new(self)
        @write_polls = Collections::Write.new(self)
        @write_polls.bond_with @read_polls
        
        @available_signals   = []
        @running_signals     = {}
        
        @available_timers    = []
        @running_timers      = {}
        
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
        
        @read_polls        = @write_polls     = \
        @available_signals = @running_signals = \
        @available_timers  = @running_timers  = nil
        
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
        @read_polls.push(Integer(fd), handler, persistent)
      end
      
      # Push the given handler for the given fd, adding if necessary.
      # If persistent is false, the handler will be popped after one trigger.
      def push_writable(fd, handler, persistent = true)
        @write_polls.push(Integer(fd), handler, persistent)
      end
      
      # Remove the next readable handler for the given fd.
      def pop_readable(fd)
        @read_polls.pop(Integer(fd))
      end
      
      # Remove the next writable handler for the given fd.
      def pop_writable(fd)
        @write_polls.pop(Integer(fd))
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
      def _read_callback(poll, rc, events)
        rescue_abort do
          @read_polls.invoke_by_addr(poll.address, rc)
        end
      end
      
      # Callback method called directly from FFI when an event is writable.
      def _write_callback(poll, rc, events)
        rescue_abort do
          @write_polls.invoke_by_addr(poll.address, rc)
        end
      end
      
      # Callback method called directly from FFI when an event is readable or writable.
      def _rw_callback(poll, rc, events)
        rescue_abort do
          if 0 != (events & FFI::UV_READABLE)
            @read_polls.invoke_by_addr(poll.address, rc)
          end
          
          if 0 != (events & FFI::UV_WRITABLE)
            @write_polls.invoke_by_addr(poll.address, rc)
          end
        end
      end
      
    end
  end
end
