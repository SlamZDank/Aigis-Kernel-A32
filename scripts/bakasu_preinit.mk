# SPDX-License-Identifier: GPL-2.0
# Loaded after upstream Kbuild, only for drivers/kernelsu with SUSFS enabled.
ifeq ($(filter preinit/preinit.o preinit/blob.o,$(kernelsu-objs)),preinit/preinit.o preinit/blob.o)
ifeq ($(strip $(KSU_SYSCALL_NO_TARGET)),)
$(error BakaSU preinit requires the upstream syscall header generator)
endif
# Upstream registers this object after its generic generated-header dependencies.
$(obj)/preinit/preinit.o: $(KSU_SYSCALL_NO_TARGET)
else
$(error BakaSU preinit is required; install target UAPI headers before building)
endif
