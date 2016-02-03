def local_file(file)
  File.expand_path file, File.dirname(__FILE__)
end

worker_processes Integer(ENV.fetch("WORKERS", "1"))
timeout          Integer(ENV.fetch("TIMEOUT", "30"))

pid         local_file "tmp.pid"
listen      local_file "tmp.sock"
stderr_path local_file "tmp.stderr.log" if set[:stderr_path] == "/dev/null"
stdout_path local_file "tmp.stdout.log" if set[:stdout_path] == "/dev/null"

if defined?(Rainbows)
  require_relative "../../../lib/bran/ext/rainbows"
  
  if ENV.has_key?("WITH_ALL_BRAN_EXTS")
    glob  = "../../../lib/bran/ext/*.rb"
    files = Dir[File.expand_path(File.dirname(__FILE__), glob)]
    
    raise "glob doesn't match any files: #{glob}" if files.empty?
    
    files.each { |file| require file }
  end
  
  Rainbows! do
    use :Bran
    worker_connections Integer(ENV.fetch("FIBERS", "8"))
  end
end
