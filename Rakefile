# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake'
require 'rdoc/task'

require_relative 'lib/god/version'

#############################################################################
#
# Helper functions
#
#############################################################################

def name
  @name ||= Dir['*.gemspec'].first.split('.').first
end

def version
  God::VERSION
end

#############################################################################
#
# Standard tasks
#
#############################################################################

task default: :test

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  file_list = FileList['test/**/test_*.rb']
  file_list = file_list.exclude('test/test_god_system.rb')
  test.test_files = file_list
  test.libs << 'lib' << 'test'
  test.verbose = true
end

Rake::TestTask.new(:system_test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_god_system.rb'
  test.verbose = true
end

Rake::RDocTask.new do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = "#{name} #{version}"
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

desc 'Open an irb session preloaded with this library'
task :console do
  sh "irb -r ./lib/#{name}.rb"
end

#############################################################################
#
# Custom tasks (add your own tasks here)
#
#############################################################################

desc 'Generate and view the site locally'
task :site do
  # Generate the dynamic parts of the site.
  puts 'Generating dynamic...'
  require 'gollum'
  wiki = Gollum::Wiki.new('.', base_path: '/doc')
  html = wiki.page('god', 'HEAD').formatted_data.tr("\342\200\231", "'")
  template = File.read('./site/index.template.html')
  index = template.sub('{{ content }}', html)
  File.write('./site/index.html', index)

  puts 'Done. Opening in browser...'
  sh 'open site/index.html'
end

desc 'Commit the local site to the gh-pages branch and deploy'
task :site_release do
  # Ensure the gh-pages dir exists so we can generate into it.
  puts 'Checking for gh-pages dir...'
  unless File.exist?('./gh-pages')
    puts 'No gh-pages directory found. Run the following commands first:'
    puts '  `git clone git@github.com:mojombo/god gh-pages'
    puts '  `cd gh-pages'
    puts '  `git checkout gh-pages`'
    exit(1)
  end

  # Copy the rest of the site over.
  puts 'Copying static...'
  sh 'cp -R site/* gh-pages/'

  # Commit the changes
  sha = `git log`.match(/[a-z0-9]{40}/)[0]
  sh "cd gh-pages && git add . && git commit -m 'Updating to #{sha}.' && git push"
  puts 'Done.'
end
