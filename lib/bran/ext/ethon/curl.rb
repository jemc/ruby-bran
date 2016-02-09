
Ethon::Curl.ffi_lib ["libcurl", "libcurl.so.4"]

Ethon::Curl.attach_function :multi_socket_action, :curl_multi_socket_action,
  [:pointer, :int, :int, :pointer], :multi_code, blocking: true

module Ethon
  module Curl
    POLL_NONE   = 0
    POLL_IN     = 1
    POLL_OUT    = 2
    POLL_INOUT  = 3
    POLL_REMOVE = 4
    
    CSELECT_IN  = 0x01
    CSELECT_OUT = 0x02
    CSELECT_ERR = 0x04
    
    SOCKET_TIMEOUT = -1
  end
end
