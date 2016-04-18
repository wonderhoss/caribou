require 'json'

module EnvironmentParser

  class EnvironmentParseError < ArgumentError; end

  def self.parseEnv(env_string)
    env = JSON.parse(env_string, :symbolize_names => true)
    validate_env(env)
    return env
  end

  def self.validate_env(env)
    if env[:name].to_s == "" then raise EnvironmentParseError.new("Environment Name is missing or empty") end
    if env[:subnet].to_s == "" then raise EnvironmentParseError.new("Subnet is required") end
    if env[:swarms].nil? || env[:swarms].length == 0 then raise EnvironmentParseError.new("Environment contains no swarms") end
    env[:swarms].each do |swarm|
      validate_swarm(swarm)
    end
  end

  def self.validate_swarm(swarm)
    if !swarm[:instance_count].nil? && !swarm[:asg].nil? then raise EnvironmentParseError.new("Cannot specify both ASG and instance count") end
    if !swarm[:instance_count].nil? && swarm[:instance_count] < 1 then raise EnvironmentParseError.new("Instance count cannot be 0") end

  end
end
