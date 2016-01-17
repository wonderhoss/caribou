module Verbose
  def logv(message = "")
    puts "  #{message}" if (!@verbose.nil? && @verbose)
  end
end
