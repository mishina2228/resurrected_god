# frozen_string_literal: true

require_relative 'helper'

class TestGodSystem < Minitest::Test
  def assert_watch_running(watch_name)
    assert God.watches[watch_name].alive?
  end

  def with_god_cleanup
    # necessary cuz actual god terminate will do exit!(0) will stops tests
    God.class_eval do
      class << self
        alias_method :orig_terminate, :terminate
        undef :terminate

        def terminate
          FileUtils.rm_f(pid) if pid
          server&.stop
        end
      end
    end
    begin
      yield
    ensure
      God.stop_all
      God.terminate # use our monkey-patched terminate
      God.watches.each_value do |w|
        w.stop_signal = 'KILL'
        w.action(:stop)
      end
      God.inited = false
      God.terminate_timeout = ::God::TERMINATE_TIMEOUT_DEFAULT
      God.internal_init # reset config, set running to false, etc.
      # set terminate back to old method, for other tests
      God.class_eval do
        class << self
          undef :terminate

          alias_method :terminate, :orig_terminate
        end
      end
    end
  end

  def test_start_running
    with_god_cleanup do
      God.start
      assert God.running
    end
  end

  def test_add_watch
    with_god_cleanup do
      God.start
      God.watch do |w|
        w.name = 'add_watch'
        w.start = File.join(GOD_ROOT, *%w[test configs complex simple_server.rb])
      end
      refute_nil God.watches['add_watch']
    end
  end

  def test_start_watch
    with_god_cleanup do
      God.start
      God.watch do |w|
        w.name = 'start_watch'
        w.start = File.join(GOD_ROOT, *%w[test configs complex simple_server.rb])
      end
      God.watches['start_watch'].action(:start)
      sleep 0.1
      assert God.watches['start_watch'].alive?
    end
  end

  def test_stop_all_with_one
    with_god_cleanup do
      God.start
      God.watch do |w|
        w.name = 'start_watch'
        w.start = File.join(GOD_ROOT, *%w[test configs complex simple_server.rb])
      end
      God.watches['start_watch'].action(:start)
      sleep 0.1
      assert God.watches['start_watch'].alive?
      assert God.stop_all, 'Should stop all watches within 10 seconds'
      assert(God.watches.none? { |_name, w| w.alive? })
    end
  end

  # default 10s timeout will expire before SIGKILL sent
  def test_stop_all_with_non_killing_signal_long_timeout
    with_god_cleanup do
      God.start
      God.watch do |w|
        w.name = 'long_timeout'
        w.stop_signal = 'USR1'
        w.stop_timeout = ::God::STOP_TIMEOUT_DEFAULT + 1
        w.start = File.join(GOD_ROOT, *%w[test configs usr1_trapper.rb])
      end
      God.watches['long_timeout'].action(:start)
      sleep 0.5
      assert God.watches['long_timeout'].alive?
      refute God.stop_all, 'long_timeout should still be alive'
      assert_watch_running('long_timeout')
    end
  end

  # use short timeout to send SIGKILL before 10s timeout
  def test_stop_all_with_non_killing_signal_short_timeout
    stop_timeout = 1
    assert_operator stop_timeout, :<, ::God::STOP_TIMEOUT_DEFAULT
    with_god_cleanup do
      God.start
      God.watch do |w|
        w.name = 'short_timeout'
        w.stop_signal = 'USR1'
        w.stop_timeout = stop_timeout
        w.start = File.join(GOD_ROOT, *%w[test configs usr1_trapper.rb])
      end
      God.watches['short_timeout'].action(:start)
      sleep 0.1
      assert God.watches['short_timeout'].alive?
      assert God.stop_all, 'Should stop all watches within 10 seconds'
      assert(God.watches.none? { |_name, w| w.alive? })
    end
  end

  # should be able to stop many simple watches within default timeout
  def test_stop_all_with_many_watches
    with_god_cleanup do
      God.start
      20.times do |i|
        God.watch do |w|
          w.name = "many_watches_#{i}"
          w.start = File.join(GOD_ROOT, *%w[test configs complex simple_server.rb])
        end
        God.watches["many_watches_#{i}"].action(:start)
      end
      Timeout.timeout(10) do # Prevent loop blocks from running infinitely
        loop do
          # Wait until all watches have started
          all_running = God.watches.select { |name, _w| name.include?('many_watches_') }.all? { |_name, w| w.alive? }
          size = God.watches.size
          break if all_running && size >= 20

          sleep 0.5
        end
      end
      assert God.stop_all, 'Should stop all watches within 10 seconds'
      assert(God.watches.none? { |_name, w| w.alive? })
    end
  end

  # should be able to stop many simple watches within short timeout
  def test_stop_all_with_many_watches_short_timeout
    with_god_cleanup do
      God.start
      God.terminate_timeout = 1
      100.times do |i|
        God.watch do |w|
          w.name = "tons_of_watches_#{i}"
          w.start = File.join(GOD_ROOT, *%w[test configs complex simple_server.rb])
          w.keepalive
        end
        God.watches["tons_of_watches_#{i}"].action(:start)
      end
      Timeout.timeout(10) do # Prevent loop blocks from running infinitely
        loop do
          # Wait until all watches have started
          watches = God.watches.select { |name, _w| name.include?('tons_of_watches_') }
          all_running = watches.all? { |_name, w| w.alive? }
          size = God.watches.size
          break if all_running && size >= 100

          puts "Alive watches: #{watches.count { |_name, w| w.alive? }}, " \
               "Not alive watches: #{watches.count { |_name, w| !w.alive? }}, " \
               "Watches: #{size}. Go to sleep..."
          sleep 2
        end
      end
      assert God.stop_all, 'Should stop all watches within 10 seconds'
      assert(God.watches.none? { |_name, w| w.alive? })
    end
  end

  def test_god_terminate_with_many_watches_short_timeout
    with_god_cleanup do
      God.start
      God.terminate_timeout = 1
      100.times do |i|
        God.watch do |w|
          w.name = "tons_of_watches_#{i}"
          w.start = File.join(GOD_ROOT, *%w[test configs complex simple_server.rb])
          w.keepalive
        end
        God.watches["tons_of_watches_#{i}"].action(:start)
      end
      Timeout.timeout(10) do # Prevent loop blocks from running infinitely
        loop do
          # Wait until all watches have started
          watches = God.watches.select { |name, _w| name.include?('tons_of_watches_') }
          all_running = watches.all? { |_name, w| w.alive? }
          size = God.watches.size
          break if all_running && size >= 100

          puts "Alive watches: #{watches.count { |_name, w| w.alive? }}, " \
               "Not alive watches: #{watches.count { |_name, w| !w.alive? }}, " \
               "Watches: #{size}. Go to sleep..."
          sleep 2
        end
      end
      begin
        God::CLI::Command.new('terminate', { port: 17165 }, [])
      rescue SystemExit
        # Ignore `exit` in `abort 'Could not stop god'`
      ensure
        assert(God.watches.none? { |_name, w| w.alive? })
      end
    end
  end
end
