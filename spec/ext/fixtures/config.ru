
run ->(req) {
  # Wait a few tens of milliseconds to simulate some backend activity.
  fm = Thread.current.thread_variable_get(:fiber_manager)
  fm.wait_for_seconds!(0.02)
  
  req_id = req["HTTP_X_REQ_ID"]
  
  headers = {"Content-Type" => "text/html"}
  headers["x-req-id"] = req_id if req_id
  
  ["200", headers, ["Rainbows Bran"]]
}
