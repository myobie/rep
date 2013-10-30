# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'rep/version'

Gem::Specification.new do |gem|
  gem.name          = "rep"
  gem.version       = Rep::VERSION
  gem.authors       = ["myobie"]
  gem.email         = ["nathan@myobie.com"]
  gem.description   = %q{A library for writing authoritative representations of objects for pages and apis.}
  gem.summary       = %q{Include Rep into any object to endow it to create json (or hashes) easily.}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'minitest'
  gem.add_development_dependency 'rocco'
  gem.add_development_dependency 'rdiscount'
end
