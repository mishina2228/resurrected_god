# frozen_string_literal: true

require_relative 'helper'

class TestContact < Minitest::Test
  def test_exists
    God::Contact
  end

  # generate

  def test_generate_should_raise_on_invalid_kind
    assert_raises(NoSuchContactError) do
      Contact.generate(:invalid)
    end
  end

  def test_generate_should_abort_on_invalid_contact
    assert_abort do
      Contact.generate(:invalid_contact)
    end
  end

  # normalize

  def test_normalize_should_accept_a_string
    input = 'tom'
    output = { contacts: ['tom'] }
    assert_equal(output, Contact.normalize(input))
  end

  def test_normalize_should_accept_an_array_of_strings
    input = %w[tom kevin]
    output = { contacts: %w[tom kevin] }
    assert_equal(output, Contact.normalize(input))
  end

  def test_normalize_should_accept_a_hash_with_contacts_string
    input = { contacts: 'tom' }
    output = { contacts: ['tom'] }
    assert_equal(output, Contact.normalize(input))
  end

  def test_normalize_should_accept_a_hash_with_contacts_array_of_strings
    input = { contacts: %w[tom kevin] }
    output = { contacts: %w[tom kevin] }
    assert_equal(output, Contact.normalize(input))
  end

  def test_normalize_should_stringify_priority
    input = { contacts: 'tom', priority: 1 }
    output = { contacts: ['tom'], priority: '1' }
    assert_equal(output, Contact.normalize(input))
  end

  def test_normalize_should_stringify_category
    input = { contacts: 'tom', category: :product }
    output = { contacts: ['tom'], category: 'product' }
    assert_equal(output, Contact.normalize(input))
  end

  def test_normalize_should_raise_on_non_string_array_hash
    input = 1
    assert_raises ArgumentError do
      Contact.normalize(input)
    end
  end

  def test_normalize_should_raise_on_non_string_array_contacts_key
    input = { contacts: 1 }
    assert_raises ArgumentError do
      Contact.normalize(input)
    end
  end

  def test_normalize_should_raise_on_non_string_containing_array
    input = [1]
    assert_raises ArgumentError do
      Contact.normalize(input)
    end
  end

  def test_normalize_should_raise_on_non_string_containing_array_contacts_key
    input = { contacts: [1] }
    assert_raises ArgumentError do
      Contact.normalize(input)
    end
  end

  def test_normalize_should_raise_on_absent_contacts_key
    input = {}
    assert_raises ArgumentError do
      Contact.normalize(input)
    end
  end

  def test_normalize_should_raise_on_extra_keys
    input = { contacts: ['tom'], priority: 1, category: 'product', extra: 'foo' }
    assert_raises ArgumentError do
      Contact.normalize(input)
    end
  end

  # notify

  def test_notify_should_be_abstract
    assert_raises(AbstractMethodNotOverriddenError) do
      Contact.new.notify(:a, :b, :c, :d, :e)
    end
  end
end
