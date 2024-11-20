# frozen_string_literal: true

require "rubygems/local_remote_options"

module Gem
  module Commands
    class AwaitCommand < Gem::Command
      include Gem::LocalRemoteOptions

      def initialize
        require "rubygems/await"
        require "bundler"

        awaiters = Rubygems::Await::Awaiter.subclasses.each_with_object({}) { |a, h| h[a.awaiter_name] = a }
        skip = ["dependency api"]
        skip.push("versions", "names", "info") unless Bundler::SharedHelpers.md5_available?

        defaults = {
          timeout: 5 * 60,
          awaiters: awaiters,
          skip: ["dependency api"],
          only: nil
        }

        super("await", "Await pushed gems being available", defaults)

        accept_uri_http

        add_option(:"Local/Remote", "-s", "--source URL", URI::HTTP,
                   "Append URL to list of remote gem sources") do |source, options|
          options[:source] = source
        end

        add_option(:Timing, "-t", "--timeout DURATION", Integer,
                   "Wait for the given duration before failing") do |timeout, options|
          options[:timeout] = timeout
        end

        add_option("--skip NAME", awaiters.keys,
                   "Skip the given awaiter") do |name, options|
          options[:skip] ||= []
          options[:skip] << name
        end

        add_option("--include NAME", awaiters.keys,
                   "Do not skip the given awaiter") do |name, options|
          options[:skip] ||= []
          options[:skip].delete(name)
        end

        add_option("--only NAME", awaiters.keys,
                   "Only run the given awaiter") do |name, options|
          options[:only] ||= []
          options[:only] << name
          options[:skip]&.delete(name)
        end
      end

      def execute
        ui = Gem.ui

        Bundler.ui # initialize
        unless defined?(Bundler::Thor::Shell::Color::UNDERLINE)
          Bundler::Thor::Shell::Color.const_set(:UNDERLINE,
                                                "\e[4m")
        end
        Bundler.ui.level = "silent" if options[:silent]

        gems = options[:args].map do |s|
          if s.end_with?(".gem")
            require "rubygems/package"
            parts = Gem::Package.new(s).spec.name_tuple.to_a.compact.map(&:to_s)
          else
            parts = s.split(":", 3)
          end
          raise Gem::CommandLineError, "Please specify a name:version[:platform], given #{s.inspect}" if parts.size < 2

          unless Gem::Version.correct?(parts[1])
            raise Gem::CommandLineError,
                  "Please specify a valid version, given #{s.inspect}"
          end

          Gem::NameTuple.new(*parts).freeze
        end.freeze

        raise Gem::CommandLineError, "Please specify at least one gem to await" if gems.empty?

        source = options[:source] || Gem.default_sources.first

        log do
          "Awaiting #{gems.map { Bundler.ui.add_color(_1.full_name, :bold) }.join(", ")} on #{Bundler.ui.add_color(
            Bundler::URICredentialsFilter.credential_filtered_uri(source), :underline
          )}"
        end

        start = Time.now
        @deadline = start + options[:timeout]

        missing = awaiters.map { _1.call(gems, source, @deadline, name_indent) }.map!(&:value)
        missing.reject!(&:empty?)

        if missing.empty?
          log do
            Bundler.ui.add_color("Found #{gems.map do |tuple|
                                            Bundler.ui.add_color(tuple.full_name, :bold, :white)
                                          end.join(", ")}", :green, :bold)
          end
        else
          all_missing = missing.flat_map do |m|
            case m
            when Set
              m.to_a
            when Hash
              m.values.flat_map(&:to_a)
            else
              raise "Unexpected #{m.inspect}"
            end
          end
          all_missing.uniq!
          all_missing.map! { Bundler.ui.add_color(_1.respond_to?(:full_name) ? _1.full_name : _1.to_s, :red, :bold) }
          log(level: "error") do
            Bundler.ui.add_color(+"Timed out", :red) << " after " <<
              Bundler.ui.add_color("#{Time.now.-(start).round(2)}s", :white, :bold) <<
              ". Check that #{all_missing.join(", ")} are published."
          end
          terminate_interaction 1
        end
      ensure
        Bundler.rubygems.ui = ui
      end

      def arguments
        "GEMNAME:VERSION[:PLATFORM]       name, version and (optional) platform of the gem to await"
      end

      def defaults_str
        %(--timeout #{options[:timeout]} #{options[:skip].map { |a| "--skip #{a.dump}" }.join(" ")})
      end

      def description
        <<~DESC
          The await command will wait for pushed gems to be available on the given
          source. It will wait for the given timeout, or 5 minutes by default.

          The available awaiters are: #{options[:awaiters].keys.join(", ")}.
        DESC
      end

      def usage
        "#{program_name} [OPTIONS] GEMNAME:VERSION[:PLATFORM] ..."
      end

      private

      def log(level: "info", tags: nil)
        return unless Bundler.ui.level(level)

        s = Time.now.to_s << " "
        case level
        when "info"
          s << Bundler.ui.add_color("I", :white)
        when "warn"
          s << Bundler.ui.add_color("W", :yellow)
        when "error"
          s << Bundler.ui.add_color("E", :red)
        when "debug"
          s << "D"
        else
          raise ArgumentError, "unhandled level #{level.inspect}"
        end
        s << (" " * (name_indent + 4))
        tags&.each do |tag|
          s << Bundler.ui.add_color("[#{tag}]", :white)
          s << " "
        end
        s << yield
        Bundler.ui.info s
      end

      def awaiters
        awaiters = options[:awaiters].values
        if options
          awaiters.select! { |a| options[:only].include?(a.awaiter_name) } if options[:only]
          awaiters.reject! { |a| options[:skip].include?(a.awaiter_name) } if options[:skip]
        end
        awaiters
      end

      def name_indent
        @name_indent ||= awaiters.map { _1.awaiter_name.size }.max || 0
      end
    end
  end
end
