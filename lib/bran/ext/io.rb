
require_relative "../../bran"
require_relative "../../bran/ext"

::Bran::Ext[:io] = true

# TODO: split to io-read.rb
Module.new do
  IO.prepend self
  
  def getbyte(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def getc(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def gets(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def read(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def readbyte(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def readchar(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def readlines(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def readpartial(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
  
  def sysread(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
end

# TODO: split to io-select.rb
Module.new do
  IO.singleton_class.prepend self
  
  def select(r_ary = nil, w_ary = nil, e_ary = nil, timeout = nil)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    return super unless fm
    
    raise NotImplementedError if e_ary && e_ary.any? # TODO: support e_ary?
    
    # TODO: move inner implementation to inside FiberManager?
    fiber  = Fiber.current
    timer  = nil
    finish = Proc.new do |item|
      begin
        r_ary.each { |io| fm.loop.pop_readable(Integer(io)) } if r_ary
        w_ary.each { |io| fm.loop.pop_writable(Integer(io)) } if w_ary
        fm.loop.pop_timable(timer) if timer
      ensure
        fiber.resume(item)
      end
    end
    
    r_ary.each do |io|
      fm.loop.push_readable(Integer(io), Proc.new { |*|
        finish.call([[io], [], []])
      })
    end if r_ary
    
    w_ary.each do |io|
      fm.loop.push_writable(Integer(io), Proc.new { |*|
        finish.call([[], [io], []])
      })
    end if w_ary
    
    if timeout
      timer = fm.loop.timer_oneshot(timeout) { timer = nil; finish.call(nil) }
    end
    
    Fiber.yield
  end
end
