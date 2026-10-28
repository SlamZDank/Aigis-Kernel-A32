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
source_status=$(git -C "$KSU" status --porcelain --untracked-files=normal)
if [ -n "$source_status" ]; then
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

# The upstream detection disables all automatic SELinux hooks. Require the
# complete parent-side set so a partial port cannot silently disable hiding.
grep -q 'susfs_selinux_setprocattr' "$ROOT/security/selinux/hooks.c"
for hook in susfs_sel_write_context susfs_sel_write_access initialize_fake_status \
            fake_status_initialize_key ksu_selinux_hide_running; do
  grep -q "$hook" "$ROOT/security/selinux/selinuxfs.c"
done
grep -q 'ksu_selinux_hide_running' "$ROOT/security/selinux/hooks.c"
grep -q 'KSU_COMPAT_HAS_SUSFS_FEATURE_SELINUX_HIDE' "$KSU/kernel/tools/susfs_compat.mk"
grep -q '#define __maybe_static$' "$KSU/kernel/feature/selinux_hide.c"
grep -q 'int ksu_handle_sys_read(unsigned int fd, char __user \*\*buf_ptr, size_t \*count_ptr)' \
  "$KSU/kernel/runtime/ksud_integration.c"
grep -q 'KSU_INSTALL_MAGIC1, 0xDEADBEEF' "$KSU/kernel/include/uapi/supercall.h"
for api in my_write_context my_write_access my_setprocattr initialize_fake_status; do
  grep -q "$api" "$KSU/kernel/feature/selinux_hide.c"
done
if grep -qE 'CMD_SUSFS_SET_PRIORITY_UID_FILTER|susfs_parse_priority_app_strings' \
  "$KSU/kernel/supercall/dispatch.c" "$KSU/kernel/manager/pkg_observer.c"; then
  echo "BakaSU now has native priority UID integration; review the parent adapter before updating" >&2
  exit 1
fi

printf 'BakaSU upstream: %s\n' "$(git -C "$KSU" rev-parse HEAD)"
printf 'BakaSU worktree: clean\n'
printf 'BakaSU integration: parent-kernel preinit, manual SELinux and SUSFS command adapters; no submodule patches\n'
printf 'SUSFS priority UID source: simonpunk gki-android12-5.10 eb95da080c76724c4962d0c62e9af3be37d9d439\n'
