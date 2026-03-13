# SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause)
# Minimal static libbpf build for resolve_btfids.

MAKEFLAGS += --no-print-directory

ifndef building_out_of_srctree
srctree := $(patsubst %/,%,$(dir $(CURDIR)))
srctree := $(patsubst %/,%,$(dir $(srctree)))
srctree := $(patsubst %/,%,$(dir $(srctree)))
endif

include $(srctree)/tools/scripts/Makefile.arch
include $(srctree)/tools/scripts/Makefile.include

ifeq ("$(origin V)", "command line")
  VERBOSE = $(V)
endif
ifndef VERBOSE
  VERBOSE = 0
endif

INCLUDES = -I. -I$(srctree)/tools/include -I$(srctree)/tools/arch/$(ARCH)/include/uapi -I$(srctree)/tools/include/uapi
LIB_FILE = libbpf.a

ifdef EXTRA_CFLAGS
  CFLAGS := $(EXTRA_CFLAGS)
else
  CFLAGS := -g -Wall
endif

override CFLAGS += $(EXTRA_WARNINGS)
override CFLAGS += -Werror -Wall
override CFLAGS += -fPIC
override CFLAGS += $(INCLUDES)
override CFLAGS += -fvisibility=hidden
override CFLAGS += -D_LARGEFILE64_SOURCE -D_FILE_OFFSET_BITS=64

ifeq ($(VERBOSE),1)
  Q =
else
  Q = @
endif

MAKEOVERRIDES=

all:

export srctree OUTPUT CC LD CFLAGS V
include $(srctree)/tools/build/Makefile.include

BPF_IN := $(OUTPUT)libbpf-in.o
LIB_FILE := $(addprefix $(OUTPUT),$(LIB_FILE))
CMD_TARGETS = $(LIB_FILE)

all: fixdep all_cmd

all_cmd: $(CMD_TARGETS)

$(BPF_IN): force
	@(test -f ../../include/uapi/linux/bpf.h -a -f ../../../include/uapi/linux/bpf.h && ( \
	(diff -B ../../include/uapi/linux/bpf.h ../../../include/uapi/linux/bpf.h >/dev/null) || \
	echo "Warning: Kernel ABI header at 'tools/include/uapi/linux/bpf.h' differs from latest version at 'include/uapi/linux/bpf.h'" >&2 )) || true
	@(test -f ../../include/uapi/linux/bpf_common.h -a -f ../../../include/uapi/linux/bpf_common.h && ( \
	(diff -B ../../include/uapi/linux/bpf_common.h ../../../include/uapi/linux/bpf_common.h >/dev/null) || \
	echo "Warning: Kernel ABI header at 'tools/include/uapi/linux/bpf_common.h' differs from latest version at 'include/uapi/linux/bpf_common.h'" >&2 )) || true
	@(test -f ../../include/uapi/linux/netlink.h -a -f ../../../include/uapi/linux/netlink.h && ( \
	(diff -B ../../include/uapi/linux/netlink.h ../../../include/uapi/linux/netlink.h >/dev/null) || \
	echo "Warning: Kernel ABI header at 'tools/include/uapi/linux/netlink.h' differs from latest version at 'include/uapi/linux/netlink.h'" >&2 )) || true
	@(test -f ../../include/uapi/linux/if_link.h -a -f ../../../include/uapi/linux/if_link.h && ( \
	(diff -B ../../include/uapi/linux/if_link.h ../../../include/uapi/linux/if_link.h >/dev/null) || \
	echo "Warning: Kernel ABI header at 'tools/include/uapi/linux/if_link.h' differs from latest version at 'include/uapi/linux/if_link.h'" >&2 )) || true
	@(test -f ../../include/uapi/linux/if_xdp.h -a -f ../../../include/uapi/linux/if_xdp.h && ( \
	(diff -B ../../include/uapi/linux/if_xdp.h ../../../include/uapi/linux/if_xdp.h >/dev/null) || \
	echo "Warning: Kernel ABI header at 'tools/include/uapi/linux/if_xdp.h' differs from latest version at 'include/uapi/linux/if_xdp.h'" >&2 )) || true
	$(Q)$(MAKE) $(build)=libbpf

$(OUTPUT)libbpf.a: $(BPF_IN)
	$(QUIET_LINK)rm -f $@; $(AR) rcs $@ $^

clean:
	$(call QUIET_CLEAN, libbpf) $(RM) *.o *~ $(CMD_TARGETS) *.a .*.d .*.cmd

PHONY += force
force:

.PHONY: $(PHONY)
