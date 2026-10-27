require 'voxpupuli/test/spec_helper'

# Messages of the Puppet warnings logged while the block runs. rspec-puppet
# compiles a catalogue only once per distinct input and reuses it afterwards,
# so the block must compile an input no earlier example has compiled.
def captured_puppet_warnings
  logs = []
  destination = Puppet::Test::LogCollector.new(logs)
  Puppet::Util::Log.newdestination(destination)
  yield
  logs.select { |log| log.level == :warning }.map(&:message)
ensure
  Puppet::Util::Log.close(destination)
end
