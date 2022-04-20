# frozen_string_literal: true

require 'rubygems'
require 'daemons'

Daemons.run_proc('daemon-polls', { dir_mode: :system }) do
  loop do
    $stdout.puts('server')
    $stdout.flush
    sleep 1
  end
end
