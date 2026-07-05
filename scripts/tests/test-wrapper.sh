#!/usr/bin/env bash
set -uo pipefail
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WRAPPER="$ROOT/claude-wrapper.sh"
passed=0 failed=0
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/claude_wrapper_test_XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
mkdir -p "$TMP_ROOT/bin" "$TMP_ROOT/work"
cp "$ROOT/tests/fake-claude.sh" "$TMP_ROOT/bin/claude"
chmod +x "$TMP_ROOT/bin/claude"
export PATH="$TMP_ROOT/bin:$PATH"
export FAKE_ARGS="$TMP_ROOT/args" FAKE_STDIN="$TMP_ROOT/stdin" FAKE_CWD="$TMP_ROOT/cwd"

check_failure() {
  local name=$1 expected=$2; shift 2
  local out code=0
  out=$("$@" 2>&1) || code=$?
  if [[ $code -ne 0 && "$out" == *"$expected"* ]]; then
    printf 'PASS %s\n' "$name"; passed=$((passed+1))
  else
    printf 'FAIL %s -- code=%s output=%s\n' "$name" "$code" "$out"; failed=$((failed+1))
  fi
}

check_success() {
  local name=$1; shift
  local out
  if out=$("$@" 2>&1); then
    printf 'PASS %s\n' "$name"; passed=$((passed+1))
  else
    printf 'FAIL %s -- output=%s\n' "$name" "$out"; failed=$((failed+1))
  fi
}

check_failure 'missing prompt emits sentinel' '[CLAUDE_WRAPPER_ERROR]' bash "$WRAPPER"
check_failure 'unsafe model emits sentinel' '[CLAUDE_WRAPPER_ERROR]' bash "$WRAPPER" --prompt x --model $'bad\nname'
check_failure 'missing context file' 'Context file not found' bash "$WRAPPER" --prompt x --context-file /definitely/missing
check_failure 'invalid timeout' 'positive integer' bash "$WRAPPER" --prompt x --timeout nope
check_failure 'invalid budget' 'greater than zero' bash "$WRAPPER" --prompt x --max-budget-usd 0
CLAUDE_WRAPPER_MODEL=env-model check_success 'CLI model overrides environment model' bash "$WRAPPER" --show-model --model cli-model
FAKE_MODE=success check_success 'success path' bash "$WRAPPER" --prompt 'request text' --context 'context text' --workdir "$TMP_ROOT/work" --model 'claude-test'
[[ $(cat "$FAKE_STDIN") == $'## Context\n\ncontext text\n\n---\n\n## Request\n\nrequest text' ]] || { printf 'FAIL stdin contract\n'; failed=$((failed+1)); }
grep -Fx -- '--tools' "$FAKE_ARGS" >/dev/null && grep -Fx -- 'claude-test' "$FAKE_ARGS" >/dev/null || { printf 'FAIL argv contract\n'; failed=$((failed+1)); }
[[ $(cat "$FAKE_CWD") == "$TMP_ROOT/work" ]] || { printf 'FAIL cwd contract\n'; failed=$((failed+1)); }
FAKE_MODE=fail check_failure 'child exit code and stderr' 'fake failure' bash "$WRAPPER" --prompt x
FAKE_MODE=empty check_failure 'empty output' 'empty output' bash "$WRAPPER" --prompt x
FAKE_MODE=sleep check_failure 'timeout' 'timed out' bash "$WRAPPER" --prompt x --timeout 1

printf 'Passed: %d; Failed: %d\n' "$passed" "$failed"
(( failed == 0 ))
