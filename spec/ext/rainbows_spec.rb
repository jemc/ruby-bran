
require_relative "../spec_helper"
require "bran/ext/rainbows"

require "net/http"

describe "bran/ext/rainbows" do
  it("registers in ::Bran::Ext") { ::Bran::Ext[:rainbows].should be }
  
  context "with an external running server" do
    shared = Proc.new do
      before(:all) do
        @fixtures_dir = File.join(File.dirname(__FILE__), "fixtures")
        
        # Find an available free port to bind to.
        @http_port = begin
          server = TCPServer.new("localhost", 0)
          server.addr[1].tap { server.close }
        end
        
        # Run the rainbows server in the background.
        system "cd #{@fixtures_dir} && "\
               "env #{env} rainbows -p #{@http_port} -D -c rainbows.conf.rb"
        
        # Wait for the server to start accepting sockets.
        begin
          TCPSocket.new("localhost", @http_port).close
        rescue SystemCallError
          retry
        end
      end
      
      after(:all) do
        # Get the pid of the server process.
        pid = File.read("#{@fixtures_dir}/tmp.pid").strip.to_i
        
        # Kill the process until it's dead.
        begin
          Process.kill("INT", pid) until `ps -q #{pid} -o pid=`.empty?
        rescue Errno::ESRCH
        end
      end
      
      it "handles a single HTTP request" do
        Net::HTTP.start "localhost", @http_port do |http|
          res = http.get("/")
          
          res.code.should eq "200"
          res.read_body.should eq "Rainbows Bran"
        end
      end
      
      it "handles concurrent HTTP requests" do
        8.times.map do |i|
          Thread.new do
            Net::HTTP.start "localhost", @http_port do |http|
              res = http.get("/")
              
              res.code.should eq "200"
              res.read_body.should eq "Rainbows Bran"
            end
          end
        end.each(&:join)
      end
    end
    
    context "with one worker and one fiber" do
      def env; "WORKERS=1 FIBERS=1" end
      instance_eval &shared
    end
    
    context "with one worker and many fibers" do
      def env; "WORKERS=1 FIBERS=8" end
      instance_eval &shared
    end
    
    context "with several workers and several fibers" do
      def env; "WORKERS=1 FIBERS=4" end
      instance_eval &shared
    end
    
    context "with one worker and one fiber, with all Bran exts" do
      def env; "WORKERS=1 FIBERS=1 WITH_ALL_BRAN_EXTS=true" end
      instance_eval &shared
    end
    
    context "with one worker and many fibers, with all Bran exts" do
      def env; "WORKERS=1 FIBERS=8 WITH_ALL_BRAN_EXTS=true" end
      instance_eval &shared
    end
    
    context "with several workers and several fibers, with all Bran exts" do
      def env; "WORKERS=4 FIBERS=4 WITH_ALL_BRAN_EXTS=true" end
      instance_eval &shared
    end
  end
  
end
