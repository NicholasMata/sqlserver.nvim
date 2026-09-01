#!/usr/bin/env sh
set -eu

project_dir=${1:?project directory is required}
attempt=0

find_leaks() {
  processes=$(ps -Ao pid=,command=) || {
    printf '%s\n' "Could not inspect processes" >&2
    exit 1
  }
  printf '%s\n' "$processes" | awk -v project_dir="$project_dir" '
    index($0, "MicrosoftSqlToolsServiceLayer") && index($0, project_dir) { print; next }
    /nvim.*runtests[.]lua/ { print }
  '
}

while [ "$attempt" -lt 20 ]; do
  leaked=$(find_leaks)
  if [ -z "$leaked" ]; then
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 0.25
done

printf '%s\n' "Leaked sqlserver.nvim test processes:" >&2
printf '%s\n' "$leaked" >&2
exit 1
