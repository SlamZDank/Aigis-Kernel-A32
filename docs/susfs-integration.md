# SUSFS on the A325X Linux 4.14 kernel

The original non-GKI integration is based on JackA1ltman commit
`dcd789634247c77d8549a42aef232c680a905585`. The priority UID filter is based on
simonpunk's `gki-android12-5.10` commit
`eb95da080c76724c4962d0c62e9af3be37d9d439` (2026-10-27). The upstream SUSFS version
string remains `v2.3.0`; it does not identify the individual feature set.

## Parent kernel adapters

BakaSU remains an unmodified upstream submodule. The parent kernel handles:

- Preinit integration and exec failure recovery, as described in
  [the preinit notes](bakasu-preinit.md).
- Native `read` and KSU `reboot` hook signatures/return handling. Normal reboot
  requests retain their kernel permission and magic checks. The KSU fd-install
  path retains its upstream permission contract.
- Manual SELinux context/access/setprocattr/status hooks. BakaSU's existing
  compatibility detector selects its supported manual SUSFS mode, publishes the
  required functions, and disables its corresponding automatic hooks. Hiding is
  selected only for app UIDs while `ksu_selinux_hide_running` is true. Policy,
  SID synchronization, feature state and fake-status initialization remain
  BakaSU implementations. This is not a fix for the previously observed
  SELinux context-parsing timing difference.
- The new priority UID command and an independent package watcher, without
  editing BakaSU's command dispatcher or package observer.

`clone_mnt()` bypasses the ordinary allocator after a SUSFS-specific allocation.
Only a clone actually reusing its parent's mount ID receives the unshared flag.
SUS_KSTAT routing uses a local variable in `vfs_getattr_nosec()` rather than
adding private bits to the user-visible statx result mask, including FD queries.

## Priority UID filter

Use a `ksu_susfs` tool containing command `0x60030` from the upstream revision
above. As root, after Android's data directories are ready:

```sh
ksu_susfs set_priority_uid_filter com.example.one,com.example.two
```

Every successful call replaces the previous list. Package names resolve from
their directory owners under `/data/data`; only app IDs 10000 through 19999 are
accepted. Leading/trailing spaces around comma-separated items are ignored.
An invalid, missing or out-of-range package rejects the new configuration and
keeps the previous filter. An empty string is rejected, matching upstream; a
list containing only empty items (for example `","`) replaces the bitmap with
an empty one. Configuration is in memory and must be reapplied after reboot.
No package is filtered until a configuration is supplied.

The filter affects UID-targeted `getpriority`, `setpriority`, `ioprio_get` and
`ioprio_set` paths for app callers, returning ESRCH for selected targets. UID
lookup normalizes the target with `% 100000` for secondary Android users.
Process/process-group requests and system/root callers retain normal behavior.
This does not hide packages from all Android APIs. The `/data/data` resolver
uses the primary user's package directories, as in the upstream implementation.

The command ABI is the upstream 65535-byte string followed by an aligned
32-bit `err` at offset 65536 (total size 65540 on arm and arm64). Payload errors
are reported through `err`; invalid reply pointers return EFAULT. Only global
UID 0 may configure it. The parent reboot adapter intercepts only this command;
existing commands continue through BakaSU.

`fs/susfs_priority.c` owns the filter and watcher. It captures Android path
references at configuration time, then resolves relative to those paths from
the worker, rather than assuming that a kworker has a userspace fs/root.
Credential overrides use BakaSU's existing KSU credentials and are reverted on
all exits; neither the caller nor the package renamer has permanent credential
changes. The dedicated fsnotify group watches `/data/system/packages.list`
replacement/write/delete events. It is separate from the sdcard monitor.

The callback only queues delayed work. The worker copies configuration under a
mutex, resolves outside it, and checks the configuration generation and event
counter before publishing. A stale snapshot is retried. Missing packages and
changed UID ranges disappear from the refreshed bitmap; transient errors retain
the existing bitmap and retry. Readers hold their own RCU section, and writers
wait for a grace period outside the configuration/fsnotify locks before freeing
the previous bitmap. The paths/group live for this built-in kernel's lifetime.

## Validation boundary

Build validation checks the manual SELinux flag, global implementation symbols,
absence of the duplicate dynamic status hook, ARM64 preinit runner, priority
filter symbols, unmodified BakaSU source and the version without `-dirty`.

Host tests use the actual modified C functions with kernel API stand-ins and
ASan/UBSan. They cover VFS routing, mount allocation, UID/payload boundaries,
allocation/lookup failures, credential cleanup, stale-refresh handling and
concurrent bitmap readers. They do not replace a device test of kernel RCU,
fsnotify event delivery, Android paths or the actual SELinux policy.

On a device check normal boot/root/preinit, Hide ON/OFF status reads and mmap,
existing SUSFS commands, the new command's four syscall paths, app reinstall/UID
changes and rapid package changes. Compare non-filtered calls and root calls
with their previous behavior. Apply real reboot or priority-changing tests only
as intentional device tests.
