desc 'Rubocop linting task'
task :rubocop do
  sh 'rubocop --fail-level C'
end

# touchstone task
task :jenkins => [:rubocop]
