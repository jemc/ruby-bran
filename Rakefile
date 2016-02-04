
require "rspec/core/rake_task"

task :default => :spec

task :vendor => :"vendor:build"
namespace :vendor do
  task :build do
    system "cd ext/libuv && rake build"
  end
  
  task :clean do
    system "cd ext/libuv && rake clean"
  end
end

RSpec::Core::RakeTask.new :spec
task :test => :spec

task :build => :vendor do
  system "rm -f *.gem"
  system "rm -rf pkg && mkdir pkg"
  system "gem build *.gemspec"
  system "mv *.gem pkg/"
end

task :g => :install
task :install => :build do
  system "gem install pkg/*.gem"
end

task :gp => :release
task :release => :install do
  system "gem push pkg/*.gem"
end
