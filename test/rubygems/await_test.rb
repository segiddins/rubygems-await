# frozen_string_literal: true

require "test_helper"

module Rubygems
  class AwaitTest < Test::Unit::TestCase
    test "VERSION" do
      assert do
        ::Rubygems::Await.const_defined?(:VERSION)
      end
    end
  end
end
