require_relative '../../utils/keyvalparse.rb'
require 'minitest/autorun'
require 'tmpdir'

# Tests for the Key/Value Parser
class TestKeyValueParser < Minitest::Spec
  test_file = File.new("#{Dir.tmpdir}/philrubytest.cfg", 'w+')
  raise IOError('Failed to create test file') unless File.writable?(test_file)
  test_file.puts ' '
  test_file.puts '  '
  test_file.puts "\t"
  test_file.puts ''
  test_file.puts 'this=isatest'
  test_file.puts 'thisis=a=test'
  test_file.puts '  spaces =  are in this bit  '
  test_file.puts "\ttabs\t=\tare\tin\tthis\tbit\t"
  test_file.close
  @@test_file = test_file.path

  Minitest::Unit.after_tests do
    begin
      File.delete(@@test_file)
    rescue
      puts 'WARN: Test config file could not be deleted.'
    end
  end

  def test_file_exists
    assert(File.exist?(@@test_file), 'Test config file was not created successfully.')
  end

  def test_parser_basic
    options = KeyValueParser.parse_file(@@test_file)
    assert_kind_of Hash, options, 'Parser did not return a hash.'
    options.wont_be_empty
    options.size.must_equal 4, 'Parser returned incorrect number of key/value pairs.'
  end

  def test_parsed_options
    options = KeyValueParser.parse_file(@@test_file)
    options.must_include :this
    options.must_include :thisis
    options.must_include :spaces
    options.must_include :tabs
    options[:this].must_equal 'isatest'
    options[:thisis].must_equal 'a=test'
    options[:spaces].must_equal 'are in this bit'
    options[:tabs].must_equal "are\tin\tthis\tbit"
  end
end
