#!/bin/sh
# Checks a module tarball for issue #68: the Forge tarball published via
# `bundle exec rake module:push` (blacksmith 8 ships an allowlisted payload;
# legacy `puppet module build` tooling reads .pmtignore) must carry the full
# payload and no dev-only paths, matching the tarball CI tests via
# `pdk build` (which reads .pdkignore).
# Usage: check-tarball.sh <tarball> [<tarball> ...]
set -e

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <tarball> [<tarball> ...]" >&2
  exit 2
fi

failed=0
for tarball in "$@"; do
echo "Tarball: ${tarball}"
contents=$(tar -tzf "${tarball}")
echo "${contents}"

for banned in 'tools/' 'TESTING.md' '.rendered-powershell' 'spec/fixtures' \
    '/pkg/' '/coverage/' '.vendor/' '/vendor/' '.bundle/' '.git/'; do
  if echo "${contents}" | grep -q "${banned}"; then
    echo "::error::Forbidden path in tarball ${tarball}: ${banned}" >&2
    failed=1
  fi
done

for required in 'metadata.json' 'manifests/' 'files/' 'templates/' 'types/' \
    'data/' 'hiera.yaml' 'lib/' 'README.md' 'CHANGELOG.md' 'LICENSE' \
    'REFERENCE.md'; do
  if ! echo "${contents}" | grep -q "${required}"; then
    echo "::error::Missing from tarball ${tarball}: ${required}" >&2
    failed=1
  fi
done
done

if [ "${failed}" -ne 0 ]; then
  exit 1
fi
echo "Tarball OK: full payload, no dev-only paths."
