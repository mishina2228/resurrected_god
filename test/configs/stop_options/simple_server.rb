#! /usr/bin/env ruby
# frozen_string_literal: true

trap :USR1 do
  # do nothing
end

loop do
  $stdout.puts('server')
  $stdout.flush

  sleep 10
end
