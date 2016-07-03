require 'json'

# Parser for environment files
module EnvironmentParser
  class EnvironmentParseError < ArgumentError; end

  def self.parse_env(env_string)
    begin
      env = JSON.parse(env_string, { symbolize_names: true })
    rescue => e
      raise EnvironmentParseError.new("Failed to parse JSON: #{e}")
    end
    validate_env(env)
    env
  end

  def self.validate_env(env)
    if env[:name].nil? || env[:name] == ''
      raise EnvironmentParseError.new('Environment Name is missing or empty')
    end
    if env[:swarms].nil? || env[:swarms].empty?
      raise EnvironmentParseError.new('Environment contains no swarms')
    end
    env[:swarms].each do |swarm|
      validate_swarm(swarm)
    end
  end

  def self.validate_swarm(swarm)
    if swarm[:name].nil? || swarm[:name] == ''
      raise EnvironmentParseError.new('Swarm Name is missing or empty')
    end
    if !swarm[:instance_count].nil? && !swarm[:asg].nil?
      raise EnvironmentParseError.new('Cannot specify both ASG and instance count') if swarm[:asg]
    end
    if swarm[:instance_count].nil? || swarm[:instance_count] < 1
      raise EnvironmentParseError.new('Instance count cannot be 0')
    end
    if swarm[:instance_type].nil? || swarm[:instance_type] == ''
      raise EnvironmentParseError.new("Instance Type is required for swarm #{swarm[:name]}")
    end
    if swarm[:role].nil? || swarm[:role] == ''
      raise EnvironmentParseError.new("Role is required for swarm #{swarm[:name]}")
    end
    if swarm[:ami].nil? || swarm[:ami] == ''
      raise EnvironmentParseError.new("AMI-ID is required for swarm #{swarm[:name]}")
    end
  end
end
