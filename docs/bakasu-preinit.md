# BakaSU preinit on the A325X Linux 4.14 kernel

The KernelSU submodule is an unmodified upstream BakaSU commit. No source patch,
compiler-time replacement or version override is applied to it. Its UAPI v6 and
embedded preinit runner remain upstream implementations. The kernel integrates
preinit and the parent adapters described in [the SUSFS notes](susfs-integration.md);
it does not add BakaSU kernel-module blacklist hooks.

## Kernel adapter

`fs/exec.c` invokes `fs/bakasu_preinit.h` for PID 1 executing `/system/bin/init`,
before the SUSFS no-su shortcut. Upstream checks argv[1] for `selinux_setup`
and consumes the staged runner once. The adapter passes a private filename,
retaining the original filename and arguments for recovery. It reserves and
zeros enough filename space for `/proc/self/fd/<int>`: upstream overwrites the
name in place without explicitly appending its terminator.

The caller releases both filename references on success. On failure it first
unwinds exec allocations and restores the file table, then closes the runner
descriptor (including fd 0). It retries the original init once, unless
`flush_old_exec()` has already replaced the old mm or a fatal signal is pending.
The adapter does not use upstream's filename-rewriting post-exec cleanup helper.

Upstream's PREINIT support flag is preserved as-is. It reports the enabled
feature, not proof that runner staging or a particular boot action succeeded.
There is no kernel-local override for the UAPI support flag.

## Build

`build_a325n.sh` checks that BakaSU is clean, installs target UAPI headers before
compilation, and checks again after building. `scripts/bakasu_preinit.mk` is
included by the parent `scripts/Makefile.build` only for the SUSFS
`drivers/kernelsu` build. It requires the runner objects and orders preinit
compilation after upstream's generated syscall header, without editing Kbuild.

For direct make builds, run from the kernel root after configuring:

```sh
sh scripts/prepare_bakasu.sh --check
make O=/absolute/path/to/output ARCH=arm64 headers_install \
  INSTALL_HDR_PATH=/absolute/path/to/output/usr
make O=/absolute/path/to/output ARCH=arm64 -j8
```

Use the same compiler settings as `build_a325n.sh` for a direct build.
`bakasu-source.txt` records the upstream SHA and unmodified source state.
The updater checks the candidate source API before updating its gitlink;
implementation changes still require review and a clean build.

## Device validation

A linked arm64 runner confirms build integration only. On the target ROM verify
that init executes `/system/bin/init selinux_setup`, that `/metadata` is mounted
then, and that the runner logs an action from a staged module's `preinit.conf`.
Use a matching UAPI v6 Manager/ksud. A prepared-module status or normal boot alone
does not confirm that the action executed. Existing module scripts keep their
normal boot phases; `kernelsu.preinit=0` disables this built-in runner.
