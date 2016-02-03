
module Bran
  class Ext
    
    class << self
      attr_accessor :check_assumptions
      
      def assume(&block)
        return unless @check_assumptions
        
        instance_eval &block
      end
      
      def check(cond)
        return if cond
        
        match = caller.first.match(/\A(.+?):(\d+):in/)
        line  = File.read(match[1]).each_line.to_a[Integer(match[2]) - 1].strip
        
        fail "Bran extension compatibility check failed: #{line}"
      end
      
      REGISTRY = {}
      
      def []=(ext_name, value)
        REGISTRY[ext_name] = value
      end
      
      def [](ext_name)
        REGISTRY[ext_name]
      end
    end
    
  end
end
