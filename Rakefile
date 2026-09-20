# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Run RuboCop"
task :lint do
  sh "rubocop"
end

desc "Run RuboCop with auto-correct"
task :"lint:fix" do
  sh "rubocop -a"
end

task default: %i[spec lint]
