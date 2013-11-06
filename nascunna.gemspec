Gem::Specification.new do |s|
  s.name        = 'nascunna'
  s.version     = '0.0.1'
  s.summary     = "System-wide caching system based on Redis"
  s.description = "Nascunna makes possible to intelligently cache every little part of your Ruby application"
  s.authors     = ["Andrea Rossi"]
  s.email       = 'andrea.rossi@lucidstack.com'
  s.files       = [
    "lib/configuration.rb",
    "lib/cacheable.rb",
    "lib/nascunna.rb",
    "nascunna.gemspec"
  ]
  # s.homepage    = 'https://rubygems.org/gems/example'
end
