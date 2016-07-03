require 'minitest/autorun'

tests_dir = Dir.new(File.dirname(__FILE__))
tests_dir.each { |file| require_relative file if file.end_with?('_test.rb') }
