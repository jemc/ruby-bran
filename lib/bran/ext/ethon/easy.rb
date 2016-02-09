
Module.new do
  Ethon::Easy.prepend self
  
  def perform
    fm = Thread.current.thread_variable_get(:fiber_manager)
    return super unless fm
    
    multi = Ethon::Multi.new
    multi.add self
    multi.perform
    
    return_code
  end
end
