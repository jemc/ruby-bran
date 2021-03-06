
require_relative "../spec_helper"
require "bran/ext/ethon"

require "socket"
require "ethon"

describe "bran/ext/ethon" do
  it("registers in ::Bran::Ext") { ::Bran::Ext[:ethon].should be }
  
  with_task_contexts do
    describe "Ethon::Easy" do
      it "works with local HTTP" do
        server = TCPServer.new("localhost", 0)
        port   = server.addr[1]
        count  = 8
        
        count.times do
          task do
            fm.wait_for_readable!(server) if fm
            client = server.accept
            
            fm.wait_for_readable!(client) if fm
            client.readpartial(0x4000).should =~ /HTTP\/1.1/
            client.write "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n"
            
            client.close
          end
        end
        
        count.times do
          task do
            easy = Ethon::Easy.new(url: "localhost:#{port}")
            easy.perform.should eq :ok
            
            easy.return_code.should eq :ok
            easy.mirror.options[:response_code].should eq 200
          end
        end
        
        after_tasks do
          server.close
          fm.stop! if fm
        end
      end
      
      it "works with remote HTTPS" do
        # We can't use multiple thread-tasks here because ethon+libcurl+SSL
        # is not threadsafe - see https://github.com/typhoeus/ethon/issues/79
        task do
          easy = Ethon::Easy.new(url: "https://www.example.com")
          easy.perform.should eq :ok
          
          easy.return_code.should eq :ok
          easy.mirror.options[:response_code].should eq 200
        end
      end
      
      it "times out with local derelict HTTP" do
        server = TCPServer.new("localhost", 0)
        port   = server.addr[1]
        count  = 8
        
        count.times do
          task do
            easy = Ethon::Easy.new(url: "localhost:#{port}", timeout_ms: 100)
            easy.perform.should eq :operation_timedout
            
            easy.return_code.should eq :operation_timedout
            easy.mirror.options[:response_code].should eq 0
          end
        end
        
        after_tasks do
          server.close
        end
      end
    end
    
    describe "Ethon::Multi" do
      it "works with local HTTP" do
        server = TCPServer.new("localhost", 0)
        port   = server.addr[1]
        count  = 8
        
        count.times do
          task do
            fm.wait_for_readable!(server) if fm
            client = server.accept
            
            fm.wait_for_readable!(client) if fm
            client.readpartial(0x4000).should =~ /HTTP\/1.1/
            client.write "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n"
            
            client.close
          end
        end
        
        task do
          multi  = Ethon::Multi.new
          easies = count.times.map do
            Ethon::Easy.new(url: "localhost:#{port}")
          end
          easies.each { |easy| multi.add easy }
          
          multi.perform
          
          easies.each do |easy|
            easy.return_code.should eq :ok
            easy.mirror.options[:response_code].should eq 200
          end
          
          server.close
        end
      end
      
      it "works with remote HTTPS" do
        count = 2
        
        task do
          multi  = Ethon::Multi.new
          easies = count.times.map do
            Ethon::Easy.new(url: "https://www.example.com")
          end
          easies.each { |easy| multi.add easy }
          
          multi.perform
          
          easies.each do |easy|
            easy.return_code.should eq :ok
            easy.mirror.options[:response_code].should eq 200
          end
        end
      end
      
      it "times out with local derelict HTTP" do
        server = TCPServer.new("localhost", 0)
        port   = server.addr[1]
        count  = 8
        
        task do
          multi  = Ethon::Multi.new
          easies = count.times.map do
            Ethon::Easy.new(url: "localhost:#{port}", timeout_ms: 100)
          end
          easies.each { |easy| multi.add easy }
          
          multi.perform
          
          easies.each do |easy|
            easy.return_code.should eq :operation_timedout
            easy.mirror.options[:response_code].should eq 0
          end
          
          server.close
        end
      end
    end
  end
end
