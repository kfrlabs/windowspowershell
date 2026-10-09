require 'puppetlabs_spec_helper/rake_tasks'

begin
  require 'puppet_blacksmith/rake_tasks'
rescue LoadError
  # puppet-blacksmith (release_prep group) is only needed to publish to the
  # Puppet Forge; its rake tasks (module:push, module:tag, ...) are simply
  # unavailable without it.
end
