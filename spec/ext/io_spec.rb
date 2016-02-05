
require_relative "../spec_helper"
require "bran/ext/io"
require "bran/ext/tcp_server"

describe "bran/ext/io + bran/ext/tcp_server" do
  it("registers in ::Bran::Ext") { ::Bran::Ext[:io].should be }
  it("registers in ::Bran::Ext") { ::Bran::Ext[:tcp_server].should be }
  
  contexts = Proc.new do
    context "with fibers (and fiber manager)" do
      let(:fm) { Bran::FiberManager.new }
      let(:tasks) { [] }
      
      def task
        tasks << Fiber.new { yield }
      end
      
      around do |example|
        fm.run! do
          example.run
          tasks.each(&:resume)
        end
      end
      
      include_examples("IO.select")
      include_examples("integration")
    end
    
    context "with threads (no fiber manager)" do
      let(:fm) { nil }
      let(:tasks) { [] }
      
      def task
        tasks << Thread.new { yield }
      end
      
      around do |example|
        example.run
        tasks.each(&:join)
      end
      
      include_examples("IO.select")
      include_examples("integration")
    end
  end
  
  shared_examples "IO.select" do
    it "can select for reading" do
      reader, writer = IO.pipe
      writer_wrote   = false
      
      task do
        r_res, w_res, e_res = IO.select([reader])
        
        writer_wrote.should == true
        
        r_res.should == [reader]
        w_res.should == []
        e_res.should == []
        
        fm.stop! if fm
      end
      
      task do
        writer_wrote = true
        writer.write("Hello!")
      end
    end
    
    it "can select for writing" do
      reader, writer = IO.pipe
      
      task do
        r_res, w_res, e_res = IO.select([], [writer])
        
        r_res.should == []
        w_res.should == [writer]
        e_res.should == []
        
        fm.stop! if fm
      end
    end
    
    it "can select reading from reading or writing" do
      reader, writer = IO.pipe
      writer_wrote   = false
      
      task do
        r_res, w_res, e_res = IO.select([reader], [reader])
        
        writer_wrote.should == true
        
        r_res.should == [reader]
        w_res.should == []
        e_res.should == []
        
        fm.stop! if fm
      end
      
      task do
        writer_wrote = true
        writer.write("Hello!")
      end
    end
    
    it "can select writing from reading or writing" do
      reader, writer = IO.pipe
      
      task do
        r_res, w_res, e_res = IO.select([writer], [writer])
        
        r_res.should == []
        w_res.should == [writer]
        e_res.should == []
        
        fm.stop! if fm
      end
    end
    
    it "can time out" do
      reader, writer = IO.pipe
      
      task do
        start = Time.now
        res   = IO.select([writer], [reader], [], 0.1)
        
        (((Time.now - start) * 10).round / 10.0).should be >= 0.1
        res.should == nil
        
        fm.stop! if fm
      end
    end
  end
  
  shared_examples "integration" do
    it "works with concurrent Net::HTTP requests" do
      server = TCPServer.new("localhost", 0)
      port   = server.addr[1]
      
      task do
        client = server.accept
        
        client.readpartial(0x4000).should =~ /HTTP\/1.1/
        client.write "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n"
        
        client.close
        server.close
      end
      
      task do
        Net::HTTP.start "localhost", port do |http|
          http.get("/").code.should eq "200"
        end
        
        fm.stop! if fm
      end
    end
  end
  
  contexts.call
end
