/* SPDX-License-Identifier: GPL-2.0 */
/* Included by exec.c after its private struct user_arg_ptr definition. */
#ifndef _FS_BAKASU_PREINIT_H
#define _FS_BAKASU_PREINIT_H

extern int ksu_setup_preinit_file(struct filename **filename_ptr,
				struct user_arg_ptr *argv);

static void bakasu_preinit_close(int *fd)
{
	if (*fd >= 0) {
		__close_fd(current->files, *fd);
		*fd = -1;
	}
}

static struct filename *bakasu_preinit_prepare(struct filename *original,
				struct user_arg_ptr *argv, int *runner_fd)
{
	struct filename *scratch;
	char expected[32];
	int fd;

	if (current->pid != 1 || IS_ERR_OR_NULL(original) ||
	    strcmp(original->name, "/system/bin/init"))
		return NULL;

	/* getname_kernel() embeds this short name in a names_cache allocation. */
	BUILD_BUG_ON(PATH_MAX - offsetof(struct filename, iname) < sizeof(expected));
	scratch = getname_kernel(original->name);
	if (IS_ERR(scratch))
		return NULL;

	/*
	 * Upstream overwrites in place without appending a NUL. Reserve and zero
	 * enough space for /proc/self/fd/ plus any nonnegative int descriptor.
	 * Never pass the caller's original (possibly audited/shared) filename.
	 */
	memset((char *)scratch->name, 0, sizeof(expected));
	strlcpy((char *)scratch->name, original->name, sizeof(expected));
	fd = ksu_setup_preinit_file(&scratch, argv);
	if (fd < 0) {
		putname(scratch);
		return NULL;
	}

	snprintf(expected, sizeof(expected), "/proc/self/fd/%d", fd);
	if (strcmp(scratch->name, expected)) {
		/* A successful upstream setup transfers a live runner fd to us. */
		bakasu_preinit_close(&fd);
		putname(scratch);
		pr_warn("BakaSU: unexpected preinit filename, booting init directly\n");
		return NULL;
	}

	*runner_fd = fd;
	return scratch;
}

#endif
