
require_relative "../../bran"
require_relative "../../bran/ext"

::Bran::Ext[:tcp_server] = true

require "socket"

Module.new do
  TCPServer.prepend self
  
  def accept(*)
    fm = Thread.current.thread_variable_get(:fiber_manager)
    fm.wait_for_readable!(to_i) if fm
    super
  end
end
