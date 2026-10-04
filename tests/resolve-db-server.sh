#!/usr/bin/env sh
set -eu

if [ -n "${DbServer:-}" ]; then
  printf '%s\n' "$DbServer"
  exit 0
fi

port=$(docker compose -f tests/integration/compose.yaml port sqlserver 1433 | awk -F: 'NF { print $NF; exit }')
case "$port" in
  ''|*[!0-9]*)
    printf 'Could not determine the local SQL Server port; start the test environment or set DbServer\n' >&2
    exit 1
    ;;
esac
printf 'localhost,%s\n' "$port"
