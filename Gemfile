source ENV['GEM_SOURCE'] || 'https://rubygems.org'

group :test do
  gem 'voxpupuli-test', '~> 8.0', require: false
  gem 'rspec-puppet-facts', require: false
  # Re-evaluated 2026-10-21 (issue #73), updated 2026-10-30 (issue #138):
  # facterdb 2.1.x pulls jgrep ~> 1.5, whose 1.5.4 `JSON.create_id = nil`
  # was removed in json >= 2.10 (NoMethodError, then "Invalid JSON given",
  # on_supported_os empty). jgrep 1.6.0 fixes it but needs Ruby >= 3.3,
  # which CI now runs alongside 3.2, so the pin below applies only to
  # Ruby < 3.3 and 3.3+ resolves jgrep 1.6.0 with an unpinned json.
  # Ruby 3.4 stays out: puppet 8 itself fails to load there ("Cannot
  # determine basic system flavour"), so 3.3 is the newest CI Ruby until
  # Puppet supports 3.4.
  gem 'json', '~> 2.9.0', require: false if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('3.3')
  # Required unconditionally by the Rakefile, so it must be installed in every
  # context that runs `rake`, including BUNDLE_WITHOUT=release_prep.
  gem 'puppetlabs_spec_helper', '>= 2.12', require: false
end

group :development do
  gem 'guard-rake', require: false
end

group :release_prep do
  gem 'puppet-blacksmith', '~> 8.0', require: false
  gem 'puppet-strings', '>= 2.2', require: false
end

puppetversion = ENV['PUPPET_GEM_VERSION']
gem 'puppet', puppetversion, require: false

