
require_relative "../../bran"
require_relative "../../bran/ext"

::Bran::Ext[:ethon] = true

require "ethon"

require_relative "ethon/curl"
require_relative "ethon/multi"
require_relative "ethon/easy"
