#!/usr/bin/env bash

# Capture one JSON document from stdin under the caller's immutable component
# deadline.  The caller owns the resulting file and must install an EXIT trap
# before invoking this function.  Nothing from stdin is written to stdout or
# diagnostics.
devfleet_capture_json_stdin() {
  local template=${1:?secret-file template required}
  local deadline_epoch=${2:?input deadline required}
  local now remaining secret_path rc=0

  [[ "$deadline_epoch" =~ ^[0-9]+$ ]] || return 64
  now=$(date +%s)
  remaining=$((deadline_epoch - now))
  (( remaining > 0 )) || return 124

  secret_path=$(mktemp "$template") || return 73
  chmod 0600 "$secret_path" || { rc=$?; rm -f -- "$secret_path"; return "$rc"; }
  timeout --foreground --kill-after=5s "${remaining}s" cat >"$secret_path" || rc=$?
  if (( rc != 0 )); then
    rm -f -- "$secret_path"
    return "$rc"
  fi
  if [[ ! -s "$secret_path" ]] || ! jq -e 'type == "object"' "$secret_path" >/dev/null 2>&1; then
    rm -f -- "$secret_path"
    return 65
  fi
  printf '%s' "$secret_path"
}
