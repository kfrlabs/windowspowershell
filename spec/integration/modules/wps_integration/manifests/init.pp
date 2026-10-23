# Fixture class for the windowspowershell integration test.
#
# Empty on purpose: the test catalog lives in spec/integration/site.pp and is
# applied with `puppet apply`. This module only carries the file sources that
# catalog references via `puppet:///modules/wps_integration/...`, so the
# windowspowershell `files/` payload shipped to the Forge stays clean.
class wps_integration {
}
