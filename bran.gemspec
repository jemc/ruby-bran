
Gem::Specification.new do |s|
  s.name         = "bran"
  s.version      = "0.0.1"
  s.date         = "2016-01-21"
  s.summary      = "bran"
  s.description  = "A source of Fiber."
  s.authors      = ["Joe McIlvain"]
  s.email        = "joe.eli.mac@gmail.com"
  
  s.files        = Dir["{lib}/**/*.rb", "bin/*", "LICENSE", "*.md"]
  s.extensions   = ["ext/libuv/Rakefile"]
  
  s.require_path = "lib"
  s.homepage     = "https://github.com/jemc/ruby-bran"
  s.licenses     = "All rights reserved." # TODO
  
  s.add_dependency "ffi", "~> 1.9", ">= 1.9.8"
  
  s.add_development_dependency "bundler",   "~>  1.6"
  s.add_development_dependency "rake",      "~> 10.3"
  s.add_development_dependency "pry",       "~>  0.9"
  s.add_development_dependency "rspec",     "~>  3.0"
  s.add_development_dependency "rspec-its", "~>  1.0"
  s.add_development_dependency "fivemat",   "~>  1.3"
end
