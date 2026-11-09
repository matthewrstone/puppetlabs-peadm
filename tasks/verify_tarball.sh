#!/bin/bash
# Checks a PE installer tarball before anything on the system is changed, so a
# truncated or corrupt download fails the plan early rather than partway
# through an upgrade (PE-42686).

fail() {
  echo "Puppet Enterprise tarball ${PT_path} failed verification: $1" >&2
  echo "Remove the file and download it again before re-running the plan." >&2
  exit 1
}

[ -f "$PT_path" ] || fail "file does not exist"
[ -s "$PT_path" ] || fail "file is empty"

if file "$PT_path" | grep -q gzip; then
  gzip -t "$PT_path" 2>/dev/null || fail "gzip integrity check failed (the file is probably truncated or corrupt)"
fi

# Reading the whole listing also catches a truncated uncompressed tar.
listing=$(tar -tf "$PT_path" 2>/dev/null) || fail "tar could not read the archive (the file is probably truncated or corrupt)"

echo "$listing" | grep -q '/puppet-enterprise-installer$' ||
  fail "archive does not contain puppet-enterprise-installer, so it is not a PE installer tarball"

size=$(stat -c%s "$PT_path" 2>/dev/null || stat -f%z "$PT_path")
echo '{ "valid": true, "size": '"$size"' }'
