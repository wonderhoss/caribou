# Mixing that provides convenient log output if verbose flag is set.
#
module Verbose
  def logv(message = '')
    puts message.to_s if !@verbose.nil? && @verbose
  end
end
