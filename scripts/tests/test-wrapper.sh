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
printf '\211PNG\r\n\032\n' >"$TMP_ROOT/first image.bin"
printf '%%PDF-1.4\n' >"$TMP_ROOT/second-document.dat"
FAKE_MODE=success check_success 'ordered media staging' bash "$WRAPPER" --prompt inspect \
  --attachment "$TMP_ROOT/first image.bin" --attachment "$TMP_ROOT/second-document.dat"
grep -Eq '1\..*mime=image/png.*support=probe-verified' "$FAKE_STDIN" &&
  grep -Eq '2\..*mime=application/pdf.*support=experimental' "$FAKE_STDIN" ||
  { printf 'FAIL media prompt contract\n'; failed=$((failed+1)); }
media_dir=$(awk 'previous == "--add-dir" { print; exit } { previous=$0 }' "$FAKE_ARGS")
grep -Fx Read "$FAKE_ARGS" >/dev/null && [[ -n "$media_dir" && ! -e "$media_dir" ]] ||
  { printf 'FAIL media argv or cleanup contract\n'; failed=$((failed+1)); }
printf '\357\273\277%s\r\n%s\r\n' "$TMP_ROOT/first image.bin" "$TMP_ROOT/second-document.dat" >"$TMP_ROOT/attachments-crlf.txt"
FAKE_MODE=success check_success 'BOM CRLF attachment list' bash "$WRAPPER" --prompt inspect \
  --attachment-list "$TMP_ROOT/attachments-crlf.txt"
grep -Eq '1\..*mime=image/png' "$FAKE_STDIN" && grep -Eq '2\..*mime=application/pdf' "$FAKE_STDIN" ||
  { printf 'FAIL attachment-list contract\n'; failed=$((failed+1)); }
mkdir -p "$TMP_ROOT/media-tmp"
printf 'RIFFxxxxWAVE' >"$TMP_ROOT/audio.wav"
TMPDIR="$TMP_ROOT/media-tmp" check_failure 'unsupported media cleanup' 'Unsupported or unrecognized media format' \
  bash "$WRAPPER" --prompt inspect --attachment "$TMP_ROOT/audio.wav"
[[ -z "$(find "$TMP_ROOT/media-tmp" -mindepth 1 -print -quit)" ]] ||
  { printf 'FAIL invalid media cleanup\n'; failed=$((failed+1)); }
check_failure 'media rejects explicit workdir' 'cannot be combined' \
  bash "$WRAPPER" --prompt inspect --workdir "$TMP_ROOT/work" --attachment "$TMP_ROOT/first image.bin"
FAKE_MODE=fail check_failure 'child exit code and stderr' 'fake failure' bash "$WRAPPER" --prompt x
FAKE_MODE=empty check_failure 'empty output' 'empty output' bash "$WRAPPER" --prompt x
FAKE_MODE=sleep check_failure 'timeout' 'timed out' bash "$WRAPPER" --prompt x --timeout 1

printf 'テスト_質問' > "$TMP_ROOT/prompt.txt"
FAKE_MODE=success check_success 'PromptFile reads UTF-8 and forwards' bash "$WRAPPER" --prompt-file "$TMP_ROOT/prompt.txt" --workdir "$TMP_ROOT/work"
grep -Fq 'テスト_質問' "$FAKE_STDIN" || { printf 'FAIL PromptFile stdin contract\n'; failed=$((failed+1)); }
check_failure 'Prompt and PromptFile are mutually exclusive' 'mutually exclusive' bash "$WRAPPER" --prompt x --prompt-file "$TMP_ROOT/prompt.txt"
check_failure 'Missing PromptFile is rejected' 'Prompt file not found' bash "$WRAPPER" --prompt-file "$TMP_ROOT/missing.txt"

printf 'Passed: %d; Failed: %d\n' "$passed" "$failed"
(( failed == 0 ))
