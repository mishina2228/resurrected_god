# frozen_string_literal: true

require 'execve'

my_env = ENV.to_hash.merge('HOME' => '/foo')
env = my_env.keys.each_with_object([]) { |k, acc| acc << "#{k}=#{my_env[k]}" }

execve(%(ruby -e "puts ENV['HOME']"), env)
