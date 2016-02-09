
require_relative "multi/bran"

Module.new do
  Ethon::Multi.prepend self
  
  def initialize(*)
    super
    
    # Create a bran performer that can steal work from this multi.
    # Fall back to normal path (no bran) if not under fiber management.
    fm = Thread.current.thread_variable_get(:fiber_manager)
    @bran = Ethon::Multi::Bran.new(fm, self) if fm
  end
  
  def perform
    # Use the bran performer instead of the normal path to perform this multi.
    # Fall back to normal path (no bran) if not under fiber management,
    # or if it fails because we are not under the same fiber manager as before.
    (@bran && @bran.perform) || super
    
    nil
  end
end
