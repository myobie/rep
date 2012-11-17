require "bundler/gem_tasks"

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

require 'rdiscount'
require 'rocco/tasks'

desc "Build Rocco Docs"
Rocco::make 'docs'

require 'fileutils'
desc "copy the rocco files from lib into the base docs folder"
task :copy_to_index do
  `cp -R docs/lib/* docs/`
  `cp docs/rep.html docs/index.html`
end

task :docs => [:rocco, :copy_to_index]

task default: 'test'
