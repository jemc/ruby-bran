
module SpecHelper
  module Task
    
    def with_task_contexts(&block)
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
        
        instance_eval(&block)
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
        
        instance_eval(&block)
      end
    end
    
  end
end
