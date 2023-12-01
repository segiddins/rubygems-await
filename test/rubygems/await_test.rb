# frozen_string_literal: true

require "test_helper"

module Rubygems
  class AwaitTest < Test::Unit::TestCase
    include Gem::DefaultUserInteraction

    def setup
      @orig_args = Gem::Command.build_args
      @orig_specific_extra_args = Gem::Command.specific_extra_args_hash.dup
      @orig_extra_args = Gem::Command.extra_args.dup

      @tmp = File.expand_path("../../tmp", __dir__)
      FileUtils.mkdir_p @tmp
      @tempdir = Dir.mktmpdir("test_rubygems_", @tmp)
      @gemhome  = File.join @tempdir, "gemhome"
      @userhome = File.join @tempdir, "userhome"
      Gem.ensure_gem_subdirectories @gemhome
      Gem.ensure_default_gem_subdirectories @gemhome

      Gem::Specification.unresolved_deps.clear

      @orig_gempath = Gem.paths
      Gem.use_paths(@gemhome)

      @orig_userhome = ENV.fetch("HOME", nil) # rubocop:disable Style/EnvHome
      ENV["HOME"] = @userhome

      FileUtils.mkdir_p @userhome

      Gem.instance_variable_set :@config_file, nil
      Gem.instance_variable_set :@user_home, nil
      Gem.instance_variable_set :@config_home, nil
      Gem.instance_variable_set :@data_home, nil

      Bundler.reset!

      super
      # common_installer_setup

      @cmd = Gem::Commands::AwaitCommand.new

      @gem_home = Gem.dir
      @gem_path = Gem.path
      @test_arch = RbConfig::CONFIG["arch"]

      @installed_specs = []
      Gem.post_install { |installer| @installed_specs << installer.spec }
    end

    def teardown
      ENV["HOME"] = @orig_userhome
      Gem.use_paths(@orig_gempath.home, *@orig_gempath.path)
      super

      # common_installer_teardown

      Gem::Command.build_args = @orig_args
      # Gem::Command.specific_extra_args_hash = @orig_specific_extra_args
      Gem::Command.extra_args = @orig_extra_args
      Gem.configuration = nil

      ::Bundler.reset!
    end

    def invoke(*args)
      @installed_specs.clear

      @cmd.invoke(*args)
    ensure
      Gem::Specification.unresolved_deps.clear
      Gem.loaded_specs.clear
      Gem.instance_variable_set(:@activated_gem_paths, 0)
      Gem.clear_default_specs
      Gem.use_paths(@gem_home, @gem_path)
      Gem.refresh
    end

    test "VERSION" do
      assert do
        ::Rubygems::Await.const_defined?(:VERSION)
      end
    end

    test "run with no args" do
      e = assert_raise Gem::CommandLineError do
        invoke
      end
      assert_equal "Please specify at least one gem to await", e.message
    end

    test "run with gems" do
      VCR.use_cassette "2023-12-01" do
        out, err = capture_output do
          invoke "bundler:2.4.22"
        end
        assert_empty err
        assert_match "Found bundler-2.4.22", out
      end
    end
  end
end
