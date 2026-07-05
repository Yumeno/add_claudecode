#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$@" > "$FAKE_ARGS"
cat > "$FAKE_STDIN"
pwd > "$FAKE_CWD"
case "${FAKE_MODE:-success}" in
  success) printf 'fake response\n' ;;
  empty) : ;;
  fail) printf 'fake failure\n' >&2; exit 7 ;;
  sleep) sleep 5 ;;
esac
