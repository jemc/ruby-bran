
module Bran
  module LibUV
    module Util
      
      def self.error_check(action_description, rc)
        raise error_create(action_description, rc) if rc < 0
      end
      
      def self.error_create(action_description, rc)
        # TODO: use appropriate SystemCallError exception class based on errno.
        name = FFI.uv_err_name(rc)
        desc = FFI.uv_strerror(rc)
        RuntimeError.new("LibUV error - while #{action_description} - #{name} - #{desc}")
      end
      
    end
  end
end
