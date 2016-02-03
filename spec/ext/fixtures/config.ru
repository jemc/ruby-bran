
run ->(req) {
  # Wait a few tens of milliseconds to simulate some backend activity.
  fm = Thread.current.thread_variable_get(:fiber_manager)
  fm.wait_for_seconds!(0.02)
  
  ['200', {'Content-Type' => 'text/html'}, ['Rainbows Bran']]
}
