
::Bran::Ext.assume do
  ::Rainbows::HttpServer.instance_method(:worker_connections).tap do |m|
    check m.owner == ::Rainbows::HttpServer
    check m.arity == 0
  end
  
  ::Rainbows::HttpServer.instance_method(:init_worker_process).tap do |m|
    check m.owner == ::Unicorn::HttpServer
    check m.arity == 1
  end
  
  ::Rainbows::HttpServer.instance_method(:reopen_worker_logs).tap do |m|
    check m.owner == ::Unicorn::HttpServer
    check m.arity == 1
  end
  
  ::Unicorn::HttpServer.instance_method(:process_client).tap do |m|
    check m.owner == ::Unicorn::HttpServer
    check m.arity == 1
  end
  
  check ::Unicorn::Worker.instance_method(:nr).arity == 0
  check ::Kgio::TCPServer.instance_method(:to_i).arity == 0
end

module Rainbows
  module Bran
    include ::Rainbows::Base
    
    def worker_loop(worker)
      readers = init_worker_process(worker)
      
      manager  = ::Bran::FiberManager.new
      stopping = false
      
      manager.run! do
        manager.loop.push_signalable :INT,  Proc.new { exit!(0) }
        manager.loop.push_signalable :TERM, Proc.new { exit!(0) }
        manager.loop.push_signalable :USR1, Proc.new { reopen_worker_logs(worker.nr) } # TODO: test
        manager.loop.push_signalable :QUIT, Proc.new { stopping = true } # TODO: test softness
        
        readers.each do |reader|
          next unless reader.is_a?(::Kgio::TCPServer) # TODO: other readers?
          
          worker_connections.times.map do |i|
            ::Fiber.new do
              until stopping # TODO: rescue and report errors here
                # Try to accept a client, then if none, wait for one to appear.
                # This may happen more than once when there all multiple
                # workers all contending for clients on the same server socket.
                until (client = reader.kgio_tryaccept)
                  manager.wait_for_readable!(reader)
                end
                
                process_client client
              end
            end.resume
          end
        end
      end
    end
    
  end
end
