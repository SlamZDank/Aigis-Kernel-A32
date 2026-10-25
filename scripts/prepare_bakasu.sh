#!/bin/sh
# Apply the parent repository's reviewed compatibility patch without changing
# the submodule commit or index. Reject unrelated edits instead of resetting them.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
KSU="$ROOT/KernelSU"
PATCH="$ROOT/patches/bakasu/0001-a325x-linux414-integration.patch"
MODE=${1:---apply}

case "$MODE" in
  --apply|--check) ;;
  *) echo "Usage: $0 [--apply|--check]" >&2; exit 2 ;;
esac

test -s "$PATCH" || { echo "Missing BakaSU compatibility patch" >&2; exit 1; }
git -C "$KSU" rev-parse --verify HEAD >/dev/null
git -C "$KSU" diff --cached --quiet || {
  echo "BakaSU has staged edits; preserve them before preparing the build" >&2
  exit 1
}
if [ -n "$(git -C "$KSU" ls-files --others --exclude-standard)" ]; then
  echo "BakaSU has untracked files; preserve them before preparing the build" >&2
  exit 1
fi

# Build the expected patched tree in a private index. This checks the complete
# tracked worktree, including edits outside files touched by the patch.
patch_index=$(mktemp)
trap 'rm -f "$patch_index" "$patch_index.lock"' EXIT HUP INT TERM
rm -f "$patch_index"
GIT_INDEX_FILE="$patch_index" git -C "$KSU" read-tree HEAD
GIT_INDEX_FILE="$patch_index" git -C "$KSU" apply --cached --check "$PATCH" || {
  echo "Compatibility patch does not apply to this BakaSU commit" >&2
  exit 1
}
GIT_INDEX_FILE="$patch_index" git -C "$KSU" apply --cached "$PATCH"

if GIT_INDEX_FILE="$patch_index" git -C "$KSU" diff --quiet; then
  echo "BakaSU compatibility patch is already applied"
elif git -C "$KSU" diff HEAD --quiet; then
  if [ "$MODE" = --apply ]; then
    git -C "$KSU" apply "$PATCH"
    GIT_INDEX_FILE="$patch_index" git -C "$KSU" diff --exit-code --quiet
    echo "Applied BakaSU compatibility patch"
  else
    echo "BakaSU compatibility patch can be applied"
  fi
else
  echo "BakaSU worktree differs from both upstream and the reviewed patch" >&2
  exit 1
fi

printf 'BakaSU upstream: %s\n' "$(git -C "$KSU" rev-parse HEAD)"
printf 'BakaSU compat SHA256: %s\n' "$(sha256sum "$PATCH" | cut -d ' ' -f 1)"
