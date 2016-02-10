
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
        
        @signal_polls = Collections::Signal.new(self)
        @timer_polls  = Collections::Timer.new(self)
        
        # TODO: add more Ruby-compatible signal handlers by default?
        push_signalable :INT, Proc.new { @abort_signal = :INT; stop! }
      end
      
      # Free the native resources associated with this object. This will
      # be done automatically on garbage collection if not called explicitly.
      def destroy
        if @finalizer
          @finalizer.call
          ObjectSpace.undefine_finalizer(self)
        end
        @ptr = @finalizer = nil
        
        @read_polls   = @write_polls = \
        @signal_polls = @timer_polls = nil
        
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
      
      # Push the given handler for the given signo, adding if necessary.
      # If persistent is false, the handler will be popped after one trigger.
      def push_signalable(signo, handler, persistent = true)
        signo = Signal.list.fetch(signo.to_s) unless signo.is_a?(Integer)
        
        @signal_polls.push(signo, handler, persistent)
      end
      
      # Push the given handler for the given timer id, adding if necessary.
      # If persistent is false, the handler will be popped after one trigger.
      def push_timable(ident, timeout, handler, persistent = true)
        @timer_polls.push(ident, handler, persistent, timeout)
      end
      
      # Remove the next readable handler for the given fd.
      def pop_readable(fd)
        @read_polls.pop(Integer(fd))
      end
      
      # Remove the next writable handler for the given fd.
      def pop_writable(fd)
        @write_polls.pop(Integer(fd))
      end
      
      # Remove the next signal handler for the given signal.
      def pop_signalable(signo)
        signo = Signal.list.fetch(signo.to_s) unless signo.is_a?(Integer)
        
        @signal_polls.pop(signo)
      end
      
      # Remove the next timer handler for the given timer.
      def pop_timable(ident)
        @timer_polls.pop(ident)
      end
      
      # Start a timer to run the given block after the given timeout.
      # The timer will be run just once, starting now.
      def timer_oneshot(time, &block)
        push_timable(block.object_id, time, block, false)
      end
      
      # Start a timer to wake the given fiber after the given timeout.
      # The timer will be run just once, starting now.
      def timer_oneshot_wake(time, fiber)
        timer_oneshot(time) { fiber.resume } # TODO: optimize this case, but be careful of ident uniqueness
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
      
      # Callback method called directly from FFI when an event is signalled.
      def _signal_callback(handle, signo)
        rescue_abort do
          @signal_polls.invoke_by_ident(signo)
        end
      end
      
      # Callback method called directly from FFI when a timer has occurred.
      def _timer_callback(handle)
        rescue_abort do
          @timer_polls.invoke_by_addr(handle.address)
        end
      end
      
    end
  end
end
