
require "fiber"

module Bran
  class FiberManager
    attr_reader :loop # TODO: hide loop when rest of interface is stable
    
    def initialize
      @loop = LibUV::Reactor.new
    end
    
    def run!
      Thread.current.thread_variable_set(:fiber_manager, self)
      
      yield if block_given?
      
      @loop.run!
    ensure
      Thread.current.thread_variable_set(:fiber_manager, nil)
    end
    
    def stop!
      Thread.current.thread_variable_set(:fiber_manager, nil)
      @loop.stop!
    end
    
    def wait_for_readable!(fd)
      @loop.push_readable(Integer(fd), ::Fiber.current, false)
      ::Fiber.yield
    end
    
    def wait_for_writable!(fd)
      @loop.push_writable(Integer(fd), ::Fiber.current, true)
      ::Fiber.yield
    end
    
    def wait_for_seconds!(seconds)
      @loop.timer_oneshot_wake(seconds, ::Fiber.current)
      ::Fiber.yield
    end
    
    def resume_soon(fiber)
      @loop.timer_oneshot_wake(0, fiber)
    end
    
  end
end
