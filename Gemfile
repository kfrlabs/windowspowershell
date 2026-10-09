source ENV['GEM_SOURCE'] || 'https://rubygems.org'

group :test do
  gem 'voxpupuli-test', '~> 8.0', require: false
  gem 'rspec-puppet-facts', require: false
  # facterdb 2.1.x pulls jgrep 1.5.x, which fails with "Invalid JSON given"
  # against json >= 2.10 and makes on_supported_os return nothing.
  gem 'json', '~> 2.9.0', require: false
end

group :development do
  gem 'guard-rake', require: false
end

group :release_prep do
  gem 'puppet-blacksmith', '~> 8.0', require: false
  gem 'puppet-strings', '>= 2.2', require: false
  gem 'puppetlabs_spec_helper', '>= 2.12', require: false
end

puppetversion = ENV['PUPPET_GEM_VERSION']
gem 'puppet', puppetversion, require: false

