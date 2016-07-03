require_relative '../../utils/keyvalparse.rb'
require 'minitest/autorun'
require 'tmpdir'

class TestKeyValueParser < Minitest::Spec
  
  testFile = File.new("#{Dir.tmpdir}/philrubytest.cfg", "w+")
  raise IOError("Failed to create test file") unless File.writable?(testFile)
  testFile.puts " "
  testFile.puts "  "
  testFile.puts "\t"
  testFile.puts ""
  testFile.puts "this=isatest"
  testFile.puts "thisis=a=test"
  testFile.puts "  spaces =  are in this bit  "
  testFile.puts "\ttabs\t=\tare\tin\tthis\tbit\t"
  testFile.close
  @@testFile = testFile.path


  Minitest::Unit.after_tests do
    begin 
     File.delete(@@testFile)
    rescue
      puts "WARN: Test config file could not be deleted."
    end
  end

      
  def test_file_exists
    assert(File.exists?(@@testFile), "Test config file was not created successfully.")
  end
  
  def test_parser_basic
    options = KeyValueParser.parse_file(@@testFile)
    assert_kind_of Hash, options, "Parser did not return a hash."
    options.wont_be_empty
    options.size.must_equal 4, "Parser returned incorrect number of key/value pairs."
  end
  
  def test_parsed_options
    options = KeyValueParser.parse_file(@@testFile)
    options.must_include :this
    options.must_include :thisis
    options.must_include :spaces
    options.must_include :tabs
    options[:this].must_equal "isatest"
    options[:thisis].must_equal "a=test"
    options[:spaces].must_equal "are in this bit"
    options[:tabs].must_equal "are\tin\tthis\tbit"
  end
  
end