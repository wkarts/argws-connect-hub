#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "HUB version validation: $*" >&2
  exit 1
}

[[ -f VERSION ]] || fail "VERSION file is missing"
canonical="$(tr -d '[:space:]' < VERSION)"
[[ "$canonical" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "VERSION must contain only release SemVer X.Y.Z; got '$canonical'"

if command -v node >/dev/null 2>&1; then
  node - "$canonical" <<'NODE'
const fs = require('fs');
const expected = process.argv[2];
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
const manifest = JSON.parse(fs.readFileSync('RELEASE-MANIFEST.json', 'utf8'));
if (pkg.version !== expected) {
  throw new Error(`package.json version ${pkg.version} != canonical VERSION ${expected}`);
}
if (manifest.version !== expected) {
  throw new Error(`RELEASE-MANIFEST version ${manifest.version} != canonical VERSION ${expected}`);
}
if (!['develop', 'stable'].includes(manifest.release_channel)) {
  throw new Error(`invalid RELEASE-MANIFEST release_channel ${manifest.release_channel}`);
}
NODE
elif command -v ruby >/dev/null 2>&1; then
  ruby -rjson - "$canonical" <<'RUBY'
expected = ARGV.fetch(0)
pkg = JSON.parse(File.read('package.json'))
manifest = JSON.parse(File.read('RELEASE-MANIFEST.json'))
raise "package.json version #{pkg['version']} != canonical VERSION #{expected}" unless pkg['version'] == expected
raise "RELEASE-MANIFEST version #{manifest['version']} != canonical VERSION #{expected}" unless manifest['version'] == expected
raise "invalid RELEASE-MANIFEST release_channel #{manifest['release_channel']}" unless %w[develop stable].include?(manifest['release_channel'])
RUBY
else
  fail "Node or Ruby is required to validate version mirrors"
fi

echo "HUB version validation: ${canonical} synchronized"
