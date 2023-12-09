# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "rubygems/await"
require "rubygems/command"
require "rubygems/commands/await_command"
require "bundler"

require "test-unit"
require "webmock/test_unit"
require "vcr"
require "tmpdir"

VCR.configure do |config|
  config.cassette_library_dir = "fixtures/vcr_cassettes"
  config.hook_into :webmock
end
