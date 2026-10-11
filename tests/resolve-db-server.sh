#!/usr/bin/env sh
set -eu

service=${1:-sqlserver}
case "$service" in
  sqlserver|sqlserver-no-agent) ;;
  *)
    printf 'Unknown SQL Server test service: %s\n' "$service" >&2
    exit 2
    ;;
esac

if [ "$service" = sqlserver ] && [ -n "${DbServer:-}" ]; then
  printf '%s\n' "$DbServer"
  exit 0
fi

port=$(docker compose -f tests/integration/compose.yaml --profile agent-unavailable port "$service" 1433 | awk -F: 'NF { print $NF; exit }')
case "$port" in
  ''|*[!0-9]*)
    printf 'Could not determine the %s host port; start its test environment\n' "$service" >&2
    exit 1
    ;;
esac
printf 'localhost,%s\n' "$port"
