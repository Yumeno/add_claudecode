#!/usr/bin/env bash
set -uo pipefail

fail() { printf '[CLAUDE_VERIFY_ERROR] %s\n' "$1"; exit 2; }
command_name=${1:-}; shift || true
repo= snapshot=; allows=()
while (($#)); do
  case "$1" in
    --repo) (($# >= 2)) || fail "missing --repo value"; repo=$2; shift 2 ;;
    --snapshot) (($# >= 2)) || fail "missing --snapshot value"; snapshot=$2; shift 2 ;;
    --allow) (($# >= 2)) || fail "missing --allow value"; allows+=("$2"); shift 2 ;;
    *) fail "unknown option: $1" ;;
  esac
done
[[ $command_name == snapshot || $command_name == check ]] || fail "command must be snapshot or check"
[[ -n $repo && -n $snapshot ]] || fail "--repo and --snapshot are required"
repo=$(cd "$repo" 2>/dev/null && pwd -P) || fail "repository not found"
top=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) || fail "not a Git repository"
top=$(cd "$top" 2>/dev/null && pwd -P) || fail "could not canonicalize repository root"
[[ $top == "$repo" ]] || fail "Repo must be the Git repository root"
snapshot_dir=$(dirname "$snapshot")
snapshot_name=$(basename "$snapshot")
snapshot_dir=$(cd "$snapshot_dir" 2>/dev/null && pwd -P) || fail "Snapshot directory does not exist"
snapshot="$snapshot_dir/$snapshot_name"
[[ $snapshot != "$repo"/* ]] || fail "Snapshot must be stored outside the repository"

is_protected() {
  local p=${1//\\//}
  local n=${p##*/}
  [[ $p == .git/config || $p == .git/hooks/* || $n == .env || $n == .env.* ||
     $n == *.pem || $n == *.key || $n == *.p12 || $n == *.pfx ]]
}

emit_state() {
  local out=$1 p rel kind hash
  {
    printf 'version\t1\nimplementation\tbash\nrepo64\t%s\n' "$(printf %s "$repo" | base64 | tr -d '\r\n')"
    printf 'head\t'; git -C "$repo" rev-parse HEAD
    printf 'branch\t'; git -C "$repo" symbolic-ref --quiet --short HEAD || true
    printf 'status64\t'; git -C "$repo" -c core.quotepath=true status --porcelain=v1 --untracked-files=all |
      base64 | tr -d '\r\n'; printf '\n'
    while IFS= read -r -d '' p; do
      rel=${p#"$repo"/}
      if is_protected "$rel"; then
        kind=file
        if [[ -L $p ]]; then kind=symlink; hash=$(printf %s "$(readlink "$p")" | sha256sum | cut -d' ' -f1)
        else hash=$(sha256sum "$p" | cut -d' ' -f1) || return 1; fi
        printf 'protected\t%s\t%s\t%s\n' "$(printf %s "$rel" | base64 | tr -d '\r\n')" "$kind" "$hash"
      fi
    done < <(find "$repo" -path "$repo/.git" -prune -o \( -type f -o -type l \) -print0)
    git_config=$(git -C "$repo" rev-parse --path-format=absolute --git-path config) || return 1
    git_hooks=$(git -C "$repo" rev-parse --path-format=absolute --git-path hooks) || return 1
    for p in "$git_config" "$git_hooks"; do
      [[ -e $p ]] || continue
      if [[ -d $p ]]; then
        while IFS= read -r -d '' p; do
          rel=".git/hooks/${p#"$git_hooks"/}"; kind=file
          if [[ -L $p ]]; then kind=symlink; hash=$(printf %s "$(readlink "$p")" | sha256sum | cut -d' ' -f1)
          else hash=$(sha256sum "$p" | cut -d' ' -f1) || return 1; fi
          printf 'protected\t%s\t%s\t%s\n' "$(printf %s "$rel" | base64 | tr -d '\r\n')" "$kind" "$hash"
        done < <(find "$p" -type f -print0)
      else
        rel=.git/config; kind=file
        if [[ -L $p ]]; then kind=symlink; hash=$(printf %s "$(readlink "$p")" | sha256sum | cut -d' ' -f1)
        else hash=$(sha256sum "$p" | cut -d' ' -f1) || return 1; fi
        printf 'protected\t%s\t%s\t%s\n' "$(printf %s "$rel" | base64 | tr -d '\r\n')" "$kind" "$hash"
      fi
    done
  } | LC_ALL=C sort > "$out"
}

if [[ $command_name == snapshot ]]; then
  ((${#allows[@]} == 0)) || fail "allow is valid only with check"
  emit_state "$snapshot" || fail "could not create snapshot"
  printf '[CLAUDE_VERIFY_OK] snapshot created\n'
  exit 0
fi
[[ -f $snapshot ]] || fail "Snapshot not found"
grep -Fqx $'implementation\tbash' "$snapshot" || fail "Snapshot implementation mismatch"
grep -Fqx $'version\t1' "$snapshot" || fail "Snapshot version mismatch"
grep -Fqx "$(printf 'repo64\t%s' "$(printf %s "$repo" | base64 | tr -d '\r\n')")" "$snapshot" ||
  fail "Snapshot repository mismatch"
current=$(mktemp) || fail "could not create temporary file"
trap 'rm -f "$current"' EXIT
emit_state "$current" || fail "could not inspect repository"

violations=()
for key in head branch; do
  [[ $(grep "^$key	" "$snapshot" || true) == $(grep "^$key	" "$current" || true) ]] ||
    violations+=("$key changed")
done
if [[ $(grep $'^status64\t' "$snapshot" || true) != $(grep $'^status64\t' "$current" || true) ]]; then
  printf '[CLAUDE_VERIFY_OK] working tree status changed\n'
fi
printf '### git status --porcelain=v1 --untracked-files=all\n'
git -C "$repo" -c core.quotepath=true status --porcelain=v1 --untracked-files=all
printf '### git diff HEAD --stat\n'
git -C "$repo" diff HEAD --stat
mapfile -t changed_lines < <(LC_ALL=C comm -3 \
  <(grep $'^protected\t' "$snapshot" | LC_ALL=C sort || true) \
  <(grep $'^protected\t' "$current" | LC_ALL=C sort || true))
changed=()
contains_exact() {
  local wanted=$1 item
  shift
  for item in "$@"; do [[ $item == "$wanted" ]] && return 0; done
  return 1
}
for line in "${changed_lines[@]}"; do
  line=${line#$'\t'}
  encoded=$(printf %s "$line" | cut -f2)
  path=$(printf %s "$encoded" | base64 -d) || fail "invalid protected path in snapshot"
  contains_exact "$path" "${changed[@]}" || changed+=("$path")
done
allowed=()
for p in "${allows[@]}"; do
  p=${p//\\//}
  [[ $p != /* && $p != *"/../"* && $p != ../* && $p != */.. &&
     $p != *[\*\?\[\]]* && $p != */ ]] || fail "Invalid or overbroad allow path: $p"
  is_protected "$p" || fail "Invalid or overbroad allow path: $p"
  contains_exact "$p" "${changed[@]}" || fail "Invalid or overbroad allow path: $p"
  allowed+=("$p")
done
for p in "${changed[@]}"; do
  if contains_exact "$p" "${allowed[@]}"; then
    printf '[CLAUDE_VERIFY_ALLOWED] protected change: %s\n' "$p"
  else
    violations+=("protected change: $p")
  fi
done
if ((${#violations[@]})); then
  printf '[CLAUDE_VERIFY_VIOLATION] %s\n' "${violations[@]}"
  exit 1
fi
printf '[CLAUDE_VERIFY_OK] no unapproved changes\n'
