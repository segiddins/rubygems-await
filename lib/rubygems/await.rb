# frozen_string_literal: true

require_relative "await/version"
require "bundler/vendored_uri"
require "rubygems/remote_fetcher"
require "set"

module Rubygems
  module Await
    URI = defined?(Gem::URI) ? Gem::URI : Bundler::URI

    class Error < StandardError; end

    class Awaiter
      unless respond_to?(:subclasses)
        def self.subclasses
          @subclasses ||= []
        end

        def inherited(klass)
          super(klass)
          subclasses << klass
        end
      end

      attr_reader :gems, :source, :deadline, :name_indent, :source_uri

      def initialize(gems, source, deadline, name_indent = 10)
        @gems = gems
        @source = source
        @source_uri = URI.parse(source)
        @deadline = deadline
        @name_indent = name_indent
      end

      def self.call(...)
        Thread.new do
          awaiter = new(...)
          Thread.current.name = "#{awaiter_name} awaiter"
          Thread.current.report_on_exception = false

          awaiter.call
        end
      end

      def collection
        Set.new(@gems)
      end

      def call
        missing = collection
        iteration = 0
        loop do
          break if missing.empty? || expired?(iteration)

          sleep iteration if iteration.positive?
          start = Time.now

          log { "#{Bundler.ui.add_color("missing", :yellow)}: #{format_element(missing)}" }
          process_collection(missing)
        rescue StandardError => e
          log_error(e) { e.full_message(highlight: false) }
        ensure
          iteration += 1
          log(level: "debug") { "##{iteration} #{Time.now.-(start).round(2)}s" } if start
        end

        if missing.empty?
          log { Bundler.ui.add_color("all found!", :green, :bold) }
        else
          log(level: "error") { "#{Bundler.ui.add_color("missing", :red, :bold)} #{format_element(missing)}" }
        end

        missing
      end

      def process_collection(missing)
        to_delete = []

        missing.each do |m|
          to_delete << m if process_element(m) && log_found(m)
        end
      ensure
        missing.subtract(to_delete)
      end

      def process_element(element)
        raise NotImplementedError
      end

      def log_found(element)
        log(level: "info") { "#{Bundler.ui.add_color("found", :green)} #{format_element(element)}" }

        true
      end

      def log_error(error, &block)
        block ||= proc { error.message.to_s }
        log(level: "warn", tags: [Bundler.ui.add_color(error.class.name, :red)], &block)
        false
      end

      def format_element(element)
        case element
        when Gem::NameTuple
          Bundler.ui.add_color element.full_name, :bold
        when Set, Array
          element.map(&method(:format_element)).join(", ")
        when Hash
          element.map { |k, v| "#{k} (#{format_element(v)})" }.join(", ")
        when String
          Bundler.ui.add_color element, :bold
        else
          element.inspect
        end
      end

      def downloader
        remote = Bundler::Source::Rubygems::Remote.new URI.parse(source)
        fetcher = Bundler::Fetcher.new(remote)
        fetcher.send(:downloader)
      end

      def compact_index_client
        remote = Bundler::Source::Rubygems::Remote.new URI.parse(source)
        fetcher = Bundler::Fetcher.new(remote)
        client =
          if Bundler::VERSION < "2.5.0"
            Bundler::Fetcher::CompactIndex.new(fetcher.send(:downloader), remote, fetcher.uri)
          else
            Bundler::Fetcher::CompactIndex.new(fetcher.send(:downloader), remote, fetcher.uri,
                                               fetcher.gem_remote_fetcher)
          end.send(:compact_index_client)
        # ensure that updating info always hits the network
        client.instance_variable_set(:@info_checksums_by_name, Hash.new { "" })
        client
      end

      def gem_remote_fetcher
        if Bundler.rubygems.respond_to?(:gem_remote_fetcher)
          Bundler.rubygems.gem_remote_fetcher
        else
          remote = Bundler::Source::Rubygems::Remote.new URI.parse(source)
          fetcher = Bundler::Fetcher.new(remote)
          raise "unsupported bundler version" unless fetcher.respond_to?(:gem_remote_fetcher)

          fetcher.gem_remote_fetcher
        end
      end

      def index_fetcher
        remote = Bundler::Source::Rubygems::Remote.new URI.parse(source)
        fetcher = Bundler::Fetcher.new(remote)
        if Bundler::VERSION < "2.5.0"
          Bundler::Fetcher::Index.new(fetcher.send(:downloader), remote, fetcher.uri)
        else
          Bundler::Fetcher::Index.new(fetcher.send(:downloader), remote, fetcher.uri, fetcher.gem_remote_fetcher)
        end
      end

      def self.awaiter_name
        raise NotImplementedError
      end

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
        s << " ["
        s << Bundler.ui.add_color(self.class.awaiter_name.rjust(name_indent, " "), :bold, :white)
        s << "] "
        tags&.each do |tag|
          s << Bundler.ui.add_color("[#{tag}]", :white)
          s << " "
        end
        s << yield
        Bundler.ui.info s
      end

      def expired?(padding = 0)
        Time.now + padding > deadline
      end

      def safe_load_marshal(contents)
        if Bundler.respond_to?(:safe_load_marshal)
          Bundler.safe_load_marshal(contents)
        else
          Marshal.load(contents) # rubocop:disable Security/MarshalLoad
        end
      end
    end

    class VersionsAwaiter < Awaiter
      def collection
        gems.group_by(&:name)
      end

      def process_collection(missing)
        versions = compact_index_client.versions
        missing.delete_if do |name, tuples|
          found = versions[name]
          tuples.delete_if do |tuple|
            found.include?(tuple.to_a - [nil, "", "ruby"]) && log_found(tuple)
          end
          tuples.empty?
        end
      end

      def self.awaiter_name
        "versions"
      end
    end

    class NamesAwaiter < Awaiter
      def collection
        Set.new gems.map(&:name)
      end

      def process_collection(missing)
        compact_index_client.names.each do |name|
          log_found(name) if missing.delete?(name)
        end
      end

      def self.awaiter_name
        "names"
      end
    end

    class InfoAwaiter < Awaiter
      def collection
        gems.group_by(&:name).transform_values! { Set.new(_1) }
      end

      def process_collection(missing)
        missing.delete_if do |name, tuples|
          process_element(name, tuples)
          tuples.empty?
        end
      end

      def process_element(name, tuples)
        cic = compact_index_client
        cic.send :update_info, name
        info = cic.instance_variable_get(:@cache).dependencies(name)

        info.each do |version, platform|
          tuple = Gem::NameTuple.new(name, version, platform)
          log_found(tuple) if tuples.delete?(tuple)
        end
      end

      def self.awaiter_name
        "info"
      end
    end

    class GemspecsAwaiter < Awaiter
      def process_element(element)
        spec = element.to_a - [nil, "ruby", ""]
        spec_file_name = "#{spec.join "-"}.gemspec"

        uri = source_uri + "#{Gem::MARSHAL_SPEC_DIR}#{spec_file_name}.rz"

        downloader.fetch(uri)
        true
      rescue (if defined?(::Bundler::Fetcher::AuthenticationForbiddenError)
                ::Bundler::Fetcher::AuthenticationForbiddenError
              else
                ::Bundler::Fetcher::AuthenticationRequiredError
              end) => e
        log_error(e) { "#{Bundler::URICredentialsFilter.credential_filtered_uri(uri)} not found" }
        false
      end

      def self.awaiter_name
        "gemspecs"
      end
    end

    class GemsAwaiter < Awaiter
      def process_element(element)
        gem_file_name = "#{element.full_name}.gem"
        src = Bundler::Source::Rubygems.new(remotes: [source])
        remote_spec = Bundler::RemoteSpecification.new(element.name, element.version, element.platform, index_fetcher)
        cache_dir = src.send(:download_cache_path, remote_spec) ||
                    src.send(:default_cache_path_for, Bundler.rubygems.gem_dir)
        local_gem_path = File.join cache_dir, gem_file_name

        remote_gem_path = source_uri + "gems/#{gem_file_name}"

        Bundler::SharedHelpers.filesystem_access(local_gem_path) do
          gem_remote_fetcher.cache_update_path remote_gem_path, local_gem_path
        end
        true
      rescue Gem::RemoteFetcher::FetchError => e
        log_error(e)
        false
      end

      def self.awaiter_name
        "gems"
      end
    end

    class FullIndexAwaiter < Awaiter
      def collection
        super.delete_if { |t| /[a-z]/i.match?(t.version.to_s) }
      end

      def process_collection(missing)
        path = source_uri + "specs.#{Gem.marshal_version}.gz"
        contents = gem_remote_fetcher.fetch_path(path)
        idx = safe_load_marshal(contents)

        idx.each do |found|
          tuple = Gem::NameTuple.new(*found.map!(&:to_s))
          log_found(tuple) if missing.delete?(tuple)
        end
      end

      def self.awaiter_name
        "full index"
      end
    end

    class PrereleaseIndexAwaiter < Awaiter
      def collection
        super.keep_if { |t| /[a-z]/i.match?(t.version.to_s) }
      end

      def process_collection(missing)
        path = source_uri + "prerelease_specs.#{Gem.marshal_version}.gz"
        contents = gem_remote_fetcher.fetch_path(path)
        idx = safe_load_marshal(contents)

        idx.each do |found|
          tuple = Gem::NameTuple.new(*found.map!(&:to_s))
          log_found(tuple) if missing.delete?(tuple)
        end
      end

      def self.awaiter_name
        "pre index"
      end
    end

    class DependencyAPIAwaiter < Awaiter
      def collection
        gems.group_by(&:name).transform_values! { Set.new(_1) }
      end

      def process_collection(missing)
        dependency_api_uri = "#{source_uri}api/v1/dependencies"
        dependency_api_uri.query = URI.encode_www_form(gems: missing.keys.sort)
        marshalled_deps = downloader.fetch(dependency_api_uri).body
        deps = safe_load_marshal(marshalled_deps)

        deps.each do |s|
          name, number, platform = s.values_at(:name, :number, :platform)
          tuple = Gem::NameTuple.new(name, number, platform)
          log_found(tuple) if missing[name].delete?(tuple)
        end

        missing.delete_if do |_name, tuples|
          tuples.empty?
        end
      end

      def self.awaiter_name
        "dependency api"
      end
    end
  end
end
