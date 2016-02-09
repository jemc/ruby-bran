
module SpecHelper
  module Task
    
    def with_task_contexts(&block)
      context "with fibers (and fiber manager)" do
        let(:fm) { Bran::FiberManager.new }
        let(:tasks) { [] }
        let(:after_tasks) { [] }
        
        def task
          tasks << Fiber.new do
            yield
            tasks.delete(Fiber.current)
            
            if tasks.empty?
              after_tasks.each(&:call)
              fm.stop!
            end
          end
        end
        
        def after_task(&block)
          after_tasks << block
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
        let(:after_tasks) { [] }
        
        def task
          tasks << Thread.new { yield }
        end
        
        def after_task(&block)
          after_tasks << block
        end
        
        around do |example|
          example.run
          tasks.each(&:join)
          after_tasks.each(&:call)
        end
        
        instance_eval(&block)
      end
    end
    
  end
end
