#!/bin/bash
# Reports whether this node's Puppet Server keeps the CA in the pe-ca database
# (PE 2026.0 and later) or on the filesystem. peadm::backup and peadm::restore
# decide from this whether to dump and restore the pe-ca database (PE-47558).
#
# The database-backed CA is switched on by an uncommented
# puppetlabs.services.ca.database-storage-service/ line in a Puppet Server
# bootstrap file. Where that line lives depends on the PE version and on how
# the node was upgraded, so every known location is checked:
#
#   /etc/puppetlabs/puppetserver/bootstrap.cfg
#   /etc/puppetlabs/puppetserver/services.d/*.cfg
#   /opt/puppetlabs/server/apps/puppetserver/config/services.d/*.cfg
#
# Output: {"backend": "database|filesystem|unknown", "source": <matched file or null>, "checked": [...]}
#   database    an uncommented line matched; "source" is the file
#   filesystem  at least one of the files exists and none has the line
#   unknown     none of the files exists, so nothing can be said; callers must
#               not assume either way
#
# PEADM_ROOT (default empty) is prefixed to every path; specs point it at a
# temp tree instead of a PE node.

root="${PEADM_ROOT:-}"
locations=(
  "${root}/etc/puppetlabs/puppetserver/bootstrap.cfg"
  "${root}/etc/puppetlabs/puppetserver/services.d/*.cfg"
  "${root}/opt/puppetlabs/server/apps/puppetserver/config/services.d/*.cfg"
)

json_string() {
  local value=${1//\\/\\\\}
  printf '"%s"' "${value//\"/\\\"}"
}

has_database_service() {
  grep -v '^[[:space:]]*#' "$1" 2>/dev/null |
    grep -q '^[[:space:]]*puppetlabs\.services\.ca\.database-storage-service/'
}

source_file=""
any_file_found=false
for location in "${locations[@]}"; do
  # The unquoted expansion is the point: it expands the *.cfg globs. A glob
  # that matches nothing stays literal, which the -f test rejects.
  for file in $location; do
    [ -f "$file" ] || continue
    any_file_found=true
    if has_database_service "$file"; then
      source_file="$file"
      break 2
    fi
  done
done

if [ -n "$source_file" ]; then
  backend=database
elif [ "$any_file_found" = true ]; then
  backend=filesystem
else
  backend=unknown
fi

printf '{"backend": "%s", "source": ' "$backend"
if [ -n "$source_file" ]; then json_string "$source_file"; else printf 'null'; fi
printf ', "checked": ['
separator=""
for location in "${locations[@]}"; do
  printf '%s' "$separator"
  json_string "$location"
  separator=", "
done
printf ']}\n'
