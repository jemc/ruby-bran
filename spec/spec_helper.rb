
require "bran"
require "bran/ext"

Bran::Ext.check_assumptions = true

require "rspec/its"
require "pry"

Thread.abort_on_exception = true

require_relative "spec_helper/task"

RSpec.configure do |c|
  # Enable "should" syntax
  c.expect_with(:rspec) { |c| c.syntax = [:should, :expect] }
  c.mock_with(:rspec)   { |c| c.syntax = [:should, :expect] }
  
  # If any tests are marked with iso:true, only run those tests
  c.filter_run_including iso:true
  c.run_all_when_everything_filtered = true
  
  # Abort after first failure
  # (Use environment variable for developer preference)
  c.fail_fast = true if ENV["RSPEC_FAIL_FAST"]
  
  # Set output formatter and enable color
  c.formatter = "Fivemat"
  c.color     = true
  
  # Extend with module helpers
  c.extend SpecHelper::Task
end
