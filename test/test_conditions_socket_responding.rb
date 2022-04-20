# frozen_string_literal: true

require_relative 'helper'

class TestConditionsSocketResponding < Minitest::Test
  # valid?

  def test_valid_should_return_false_if_no_options_set
    c = Conditions::SocketResponding.new
    c.watch = stub(name: 'foo')
    refute c.valid?
  end

  def test_valid_should_return_true_if_required_options_set_for_default
    c = Conditions::SocketResponding.new
    c.port = 443
    assert c.valid?
  end

  def test_valid_should_return_true_if_required_options_set_for_tcp
    c = Conditions::SocketResponding.new
    c.family = 'tcp'
    c.port = 443
    assert c.valid?
  end

  def test_valid_should_return_true_if_required_options_set_for_unix
    c = Conditions::SocketResponding.new
    c.path = 'some-path'
    c.family = 'unix'
    assert c.valid?
  end

  def test_valid_should_return_true_if_family_is_tcp
    c = Conditions::SocketResponding.new
    c.port = 443
    c.family = 'tcp'
    assert c.valid?
  end

  def test_valid_should_return_true_if_family_is_unix
    c = Conditions::SocketResponding.new
    c.path = 'some-path'
    c.family = 'unix'
    c.watch = stub(name: 'foo')
    assert c.valid?
  end

  # socket method
  def test_socket_should_return_127_0_0_1_for_default_addr
    c = Conditions::SocketResponding.new
    c.socket = 'tcp:443'
    assert_equal '127.0.0.1', c.addr
  end

  def test_socket_should_set_properties_for_tcp
    c = Conditions::SocketResponding.new
    c.socket = 'tcp:127.0.0.1:443'
    assert_equal 'tcp', c.family
    assert_equal '127.0.0.1', c.addr
    assert_equal 443, c.port
    refute c.responding
    # path should not be set for tcp sockets
    assert_nil c.path
  end

  def test_socket_should_set_properties_for_unix
    c = Conditions::SocketResponding.new
    c.socket = 'unix:/tmp/process.sock'
    assert_equal 'unix', c.family
    assert_equal '/tmp/process.sock', c.path
    refute c.responding
    # path should not be set for unix domain sockets
    assert_equal 0, c.port
  end

  # test : responding = false

  def test_test_tcp_should_return_false_if_socket_is_listening
    c = Conditions::SocketResponding.new
    c.prepare

    TCPSocket.expects(:new).returns(0)
    refute c.test
  end

  def test_test_tcp_should_return_true_if_no_socket_is_listening
    c = Conditions::SocketResponding.new
    c.prepare

    TCPSocket.expects(:new).returns(nil)
    assert c.test
  end

  def test_test_unix_should_return_false_if_socket_is_listening
    c = Conditions::SocketResponding.new
    c.socket = 'unix:/some/path'

    c.prepare
    UNIXSocket.expects(:new).returns(0)
    refute c.test
  end

  def test_test_unix_should_return_true_if_no_socket_is_listening
    c = Conditions::SocketResponding.new
    c.socket = 'unix:/some/path'
    c.prepare

    UNIXSocket.expects(:new).returns(nil)
    assert c.test
  end

  def test_test_unix_should_return_true_if_socket_is_listening_2_times
    c = Conditions::SocketResponding.new
    c.socket = 'unix:/some/path'
    c.times = [2, 2]
    c.prepare

    UNIXSocket.expects(:new).returns(nil).times(2)
    refute c.test
    assert c.test
  end

  # test : responding = true

  def test_test_tcp_should_return_true_if_socket_is_listening_with_responding_true
    c = Conditions::SocketResponding.new
    c.responding = true
    c.prepare

    TCPSocket.expects(:new).returns(0)
    assert c.test
  end

  def test_test_tcp_should_return_false_if_no_socket_is_listening_with_responding_true
    c = Conditions::SocketResponding.new
    c.responding = true
    c.prepare

    TCPSocket.expects(:new).returns(nil)
    refute c.test
  end

  def test_test_unix_should_return_true_if_socket_is_listening_with_responding_true
    c = Conditions::SocketResponding.new
    c.responding = true
    c.socket = 'unix:/some/path'

    c.prepare
    UNIXSocket.expects(:new).returns(0)
    assert c.test
  end

  def test_test_unix_should_return_false_if_no_socket_is_listening_with_responding_true
    c = Conditions::SocketResponding.new
    c.socket = 'unix:/some/path'
    c.responding = true
    c.prepare

    UNIXSocket.expects(:new).returns(nil)
    refute c.test
  end

  def test_test_unix_should_return_false_if_socket_is_listening_2_times_with_responding_true
    c = Conditions::SocketResponding.new
    c.socket = 'unix:/some/path'
    c.responding = true
    c.times = [2, 2]
    c.prepare

    UNIXSocket.expects(:new).returns(nil).times(2)
    refute c.test
    refute c.test
  end
end
