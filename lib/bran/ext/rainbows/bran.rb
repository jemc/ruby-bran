
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
      
      # We have to skip the implementation from Rainbows::Base,
      # and use the implementation from Unicorn::HttpServer directly.
      process_client = ::Unicorn::HttpServer.instance_method(:process_client)
      process_client = process_client.bind(self)
      
      manager  = ::Bran::FiberManager.new
      stopping = false
      
      manager.run! do
        manager.loop.signal_start(:INT)  { exit!(0) }
        manager.loop.signal_start(:TERM) { exit!(0) }
        manager.loop.signal_start(:USR1) { reopen_worker_logs(worker.nr) } # TODO: test
        manager.loop.signal_start(:QUIT) { stopping = true } # TODO: test softness
        
        readers.each do |reader|
          next unless reader.is_a?(::Kgio::TCPServer) # TODO: other readers?
          
          worker_connections.times.map do |i|
            ::Fiber.new do
              until stopping # TODO: rescue and report errors here
                manager.wait_for_readable!(reader)
                process_client.call(reader.kgio_accept)
              end
            end.resume
          end
        end
      end
    end
    
  end
end
