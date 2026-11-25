#!/bin/sh
# Validate the unmodified upstream submodule and the parent-kernel integration.
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

# BakaSU from 16 Nov 2026 hides its SELinux domain itself on 4.14 ("auto"
# mode). The parent must not publish the old manual-hook API, otherwise
# BakaSU's compat detection selects the manual mode and disables auto hiding.
if grep -q 'susfs_selinux_setprocattr\|ksu_selinux_hide_running' \
  "$ROOT/security/selinux/hooks.c"; then
  echo "Parent still has the manual SELinux setprocattr hook" >&2
  exit 1
fi
for hook in my_write_context my_write_access fake_status_initialize_key \
            ksu_selinux_hide_running fake_status initialize_fake_status; do
  if grep -q "$hook" "$ROOT/security/selinux/selinuxfs.c"; then
    echo "Parent still has the manual SELinux hook '$hook'" >&2
    exit 1
  fi
done
if grep -q 'my_setprocattr\|my_write_context\|my_write_access\|initialize_fake_status\|ksu_selinux_hide_running' \
  "$ROOT/include/linux/susfs_ksu.h"; then
  echo "Parent still declares the manual SELinux hook API" >&2
  exit 1
fi

# BakaSU's auto SELinux hide requires the SUSFS v2.4.0 exports.
test -s "$KSU/kernel/feature/selinux_hide/selinux_hide_auto.c"
for api in susfs_add_sus_type susfs_add_sus_avd_allowed_by_type; do
  grep -q "$api" "$KSU/kernel/selinux/sepolicy.c" || {
    echo "BakaSU auto SELinux hide does not use '$api'; review the kernel core" >&2
    exit 1
  }
  grep -q "$api" "$ROOT/fs/susfs.c" || {
    echo "SUSFS core does not export '$api' required by BakaSU" >&2
    exit 1
  }
done

# BakaSU dispatches the SUSFS commands natively; the parent must not intercept
# the priority UID filter in the reboot syscall anymore.
for cmd in CMD_SUSFS_SET_PRIORITY_UID_FILTER CMD_SUSFS_SET_SUS_PATH_UID_FILTER; do
  grep -q "$cmd" "$KSU/kernel/supercall/dispatch.c" || {
    echo "BakaSU does not dispatch '$cmd'; review the SUSFS core" >&2
    exit 1
  }
done
for parser in susfs_parse_priority_app_strings susfs_parse_sus_path_app_strings; do
  grep -q "$parser" "$KSU/kernel/manager/throne_tracker.c" || {
    echo "BakaSU does not call '$parser'; review the SUSFS package tracker" >&2
    exit 1
  }
  grep -q "$parser" "$ROOT/fs/susfs.c" || {
    echo "SUSFS core does not provide '$parser' required by BakaSU" >&2
    exit 1
  }
done
grep -q 'CMD_SUSFS_SET_PRIORITY_UID_FILTER' "$ROOT/kernel/reboot.c" && {
  echo "Parent still intercepts CMD_SUSFS_SET_PRIORITY_UID_FILTER" >&2
  exit 1
}

# The v2.4.0 core includes the priority filter; the old parent copy must be gone.
test ! -e "$ROOT/fs/susfs_priority.c"
if grep -q 'susfs_priority\.o' "$ROOT/fs/Makefile"; then
  echo "fs/Makefile still builds the removed susfs_priority.o" >&2
  exit 1
fi
grep -q 'CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER' "$ROOT/kernel/sys.c"
grep -q 'CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER' "$ROOT/block/ioprio.c"
grep -q '^CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER=y$' \
  "$ROOT/arch/arm64/configs/a32_slamzdank_defconfig"
grep -q 'susfs_set_priority_uid_filter' "$ROOT/fs/susfs.c"
grep -q 'susfs_set_sus_path_uid_filter' "$ROOT/fs/susfs.c"

# 4.14.357 has the 4-argument kernel_read(); the core falls back to the old
# signature unless the build passes SUSFS_KERNEL_READ_NEW.
grep -q 'SUSFS_KERNEL_READ_NEW' "$ROOT/fs/Makefile"
grep -q 'SUSFS_KERNEL_READ_NEW' "$ROOT/fs/susfs.c"
grep -q 'SUSFS_VERSION "v2.4.0"' "$ROOT/include/linux/susfs.h"

test -s "$KSU/kernel/preinit/runner/runner.c"
grep -q 'int ksu_handle_sys_read(unsigned int fd, char __user \*\*buf_ptr, size_t \*count_ptr)' \
  "$KSU/kernel/runtime/ksud_integration.c"
grep -q 'KSU_INSTALL_MAGIC1, 0xDEADBEEF' "$KSU/kernel/include/uapi/supercall.h"

printf 'BakaSU upstream: %s\n' "$(git -C "$KSU" rev-parse HEAD)"
printf 'BakaSU worktree: clean\n'
printf 'BakaSU integration: parent-kernel preinit, auto SELinux hide, native SUSFS command dispatch; no submodule patches\n'
printf 'SUSFS core: v2.4.0 (JackA1ltman 4.14 port), priority and sus_path UID filters\n'
