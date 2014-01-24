require "bundler/gem_tasks"

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
  t.verbose = true
end

desc "Build Docco Docs"
task :docco do
  `docco lib/**/*.rb`
end

require 'fileutils'
desc "copy the rep.html to index.html"
task :copy_to_index do
  `cp docs/rep.html docs/index.html`
end

task :docs => [:docco, :copy_to_index]

task :default => 'test'
