#!/bin/sh
# Validate the unmodified upstream submodule; all adaptation lives in the kernel.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
KSU="$ROOT/KernelSU"

case "${1:---check}" in
  --check) ;;
  *) echo "Usage: $0 [--check]" >&2; exit 2 ;;
esac

git -C "$KSU" rev-parse --verify HEAD >/dev/null
if [ -n "$(git -C "$KSU" status --porcelain --untracked-files=normal)" ]; then
  echo "BakaSU must match its upstream commit; preserve local edits before building" >&2
  exit 1
fi

# Check the API used by fs/bakasu_preinit.h before accepting an update. A full
# clean build is still required to validate a new upstream implementation.
grep -q 'int ksu_setup_preinit_file(struct filename \*\*filename_ptr, struct user_arg_ptr \*argv_user)' \
  "$KSU/kernel/preinit/preinit.c" || {
  echo "BakaSU SUSFS preinit setup API changed; review the kernel adapter" >&2
  exit 1
}
grep -q 'KSU_SYSCALL_NO_TARGET :=' \
  "$KSU/kernel/tools/code_generation/syscall_no/syscall_no.mk" || {
  echo "BakaSU syscall generator changed; review the kernel build dependency" >&2
  exit 1
}
test -s "$KSU/kernel/preinit/runner/runner.c"
test -s "$KSU/kernel/tools/code_generation/preinit_runner/preinit_runner.mk"

printf 'BakaSU upstream: %s\n' "$(git -C "$KSU" rev-parse HEAD)"
printf 'BakaSU worktree: clean\n'
printf 'BakaSU integration: parent-kernel preinit adapter; no submodule patches\n'
