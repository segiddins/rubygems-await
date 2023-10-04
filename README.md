# `rubygems-await`

## Installation

Install the gem and add to the application's Gemfile by executing:

    $ bundle add rubygems-await

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install rubygems-await

## Usage

```
Usage: gem await [OPTIONS] GEMNAME:VERSION[:PLATFORM] ... [options]

  Options:
        --skip NAME                  Skip the given awaiter
        --include NAME               Do not skip the given awaiter
        --only NAME                  Only run the given awaiter


  Local/Remote Options:
    -s, --source URL                 Append URL to list of remote gem sources


  Timing Options:
    -t, --timeout DURATION           Wait for the given duration before failing


  Common Options:
    -h, --help                       Get help on this command
    -V, --[no-]verbose               Set the verbose level of output
    -q, --quiet                      Silence command progress meter
        --silent                     Silence RubyGems output
        --config-file FILE           Use this config file instead of default
        --backtrace                  Show stack backtrace on errors
        --debug                      Turn on Ruby debugging
        --norc                       Avoid loading any .gemrc file


  Arguments:
    GEMNAME:VERSION[:PLATFORM]       name, version and (optional) platform of the gem to await

  Summary:
    Await pushed gems being available

  Description:
    The await command will wait for pushed gems to be available on the given
    source. It will wait for the given timeout, or 5 minutes by default.

    The available awaiters are: dependency api, pre index, full index, gems,
    gemspecs, info, names, versions.

  Defaults:
    --timeout 300 --skip "dependency api"
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test-unit` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/segiddins/rubygems-await. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/segiddins/rubygems-await/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rubygems::Await project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/segiddins/rubygems-await/blob/main/CODE_OF_CONDUCT.md).
