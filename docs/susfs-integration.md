# SUSFS on the A325X Linux 4.14 kernel

The core files (`fs/susfs.c`, `include/linux/susfs.h`,
`include/linux/susfs_def.h`) are JackA1ltman's non-GKI 4.14 port of SUSFS
**v2.4.0**, from commit
`ec069a4e34f992d602a6b40d2e211df2516e2865` (2026-11-18). The rest of the
kernel keeps the existing 4.14 hook layout for that port.

Parent-side additions on top of the upstream core:

- `getname_safe`/`putname_safe` helpers for this tree's namei call sites.
- `susfs_get_data_path()` for the `fs/readdir.c` sus-path hooks.
- No-op `SUSFS_LOGI_RL`/`SUSFS_LOGE_RL` macros when logging is disabled.
- `SUSFS_KERNEL_READ_NEW`, because 4.14.357 has the four-argument
  `kernel_read()`. `fs/Makefile` detects the signature and defines it.

## Parent kernel adapters

BakaSU remains an unmodified upstream submodule. The parent kernel handles:

- Preinit integration and exec failure recovery, as described in
  [the preinit notes](bakasu-preinit.md).
- Native `read` and KSU `reboot` hook signatures/return handling. Normal reboot
  requests retain their kernel permission and magic checks. The KSU fd-install
  path retains its upstream permission contract.
- Forwarding of every `SUSFS_MAGIC` command to BakaSU. BakaSU requires global
  UID 0 and dispatches the commands itself; the parent no longer intercepts
  the priority UID filter command.

`clone_mnt()` bypasses the ordinary allocator after a SUSFS-specific allocation.
Only a clone actually reusing its parent's mount ID receives the unshared flag.
SUS_KSTAT routing uses a local variable in `vfs_getattr_nosec()` rather than
adding private bits to the user-visible statx result mask, including FD queries.

## SELinux hide

BakaSU since 16 November 2026 hooks selinuxfs and `setprocattr` itself on 4.14
("auto" mode). The kernel only provides the SUSFS v2.4.0 exports that BakaSU's
policy loader uses:

- `susfs_add_sus_type()` for the hidden su domain type.
- `susfs_add_sus_avd_allowed_by_type()` for the original AV decision.

The parent must not publish the old manual-hook API
(`ksu_selinux_hide_running`, `fake_status`, `my_write_context`,
`my_write_access`, `my_setprocattr`). BakaSU's build checks
`security/selinux/hooks.c` for that API; if present it selects the manual mode
and disables its own automatic hooks.

## Priority UID filter

Use a `ksu_susfs` tool containing command `0x60030` from SUSFS v2.4.0. As root,
after Android's data directories are ready:

```sh
ksu_susfs set_priority_uid_filter com.example.one,com.example.two
```

Every successful call replaces the previous list. Package names resolve from
`/data/system/packages.list`; only app IDs 10000 through 19999 are accepted.
Leading/trailing spaces around comma-separated items are ignored. An empty
string is rejected. Entries that are invalid, missing or out of range are
skipped, as in upstream v2.4.0; a list that resolves to nothing installs an
empty bitmap. Configuration is in memory and must be reapplied after reboot.
No package is filtered until a configuration is supplied.

The filter affects UID-targeted `getpriority`, `setpriority`, `ioprio_get` and
`ioprio_set` paths for app callers, returning ESRCH for selected targets. UID
lookup normalizes the target with `% 100000` for secondary Android users.
Process/process-group requests and system/root callers retain normal behavior.
This does not hide packages from all Android APIs.

BakaSU dispatches the command and re-resolves the stored package names through
`susfs_parse_priority_app_strings()` when its package tracker sees an install
or uninstall. The resolver switches to the KernelSU SELinux domain while
reading `packages.list`, and a serialized worker avoids concurrent refreshes.
Readers use RCU and see either the old or the new bitmap, never a freed one.

## Sus-path UID filter

SUSFS v2.4.0 adds command `0x55554`. The configured package list is an
**allowlist of apps that may still see sus paths**:

```sh
ksu_susfs set_sus_path_uid_filter com.example.one
```

The filter uses UIDs 10000 through 19999, resolves names from
`/data/system/packages.list`, and refreshes the same way as the priority
filter (`susfs_parse_sus_path_app_strings()`). Processes below UID 10000 are
not affected; UIDs 90000 and above are always allowed.

This is a behavior change from v2.3.0, where a sus path was hidden only from
apps other than its owner. With v2.4.0 an app process in the 10000-89999 range
does not see a sus path unless it is on the allowlist. Userspace tooling that
adds sus paths must configure the filter, or the owning app loses visibility.

## Validation boundary

Build validation (`scripts/prepare_bakasu.sh` and the CI verify step) checks:

- The unmodified BakaSU source, preinit API and UAPI magic.
- Absence of the manual SELinux hook API and the old
  `fs/susfs_priority.c`.
- The v2.4.0 exports BakaSU needs (`susfs_add_sus_type`,
  `susfs_add_sus_avd_allowed_by_type`, the two command parsers).
- `CONFIG_KSU_SUSFS_PRIORITY_UID_FILTER` in the defconfig and the
  `kernel_read` compatibility flag.
- The syscall-side priority filter symbols in the built kernel.

These checks do not replace a device test of kernel RCU, Android paths,
`packages.list` behavior or the actual SELinux policy.

On a device check normal boot/root/preinit, Hide ON/OFF status reads and mmap,
existing SUSFS commands, both new filters, app reinstall/UID changes and rapid
package changes. Compare non-filtered calls and root calls with their previous
behavior. Apply real reboot or priority-changing tests only as intentional
device tests.
