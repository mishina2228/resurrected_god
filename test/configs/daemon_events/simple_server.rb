# frozen_string_literal: true

require 'rubygems'
require 'daemons'

puts 'simple server ahoy!'

Daemons.run_proc('daemon-events', { dir_mode: :system }) do
  loop do
    puts 'server'
    sleep 1
  end
end
