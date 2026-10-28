// SPDX-License-Identifier: GPL-2.0
/*
 * SUSFS priority UID filter, adapted from simonpunk eb95da0 for Linux 4.14.
 * The parent kernel owns command dispatch and package observation so BakaSU
 * can remain an unmodified submodule.
 */
#include <linux/bitmap.h>
#include <linux/cred.h>
#include <linux/fs.h>
#include <linux/fsnotify_backend.h>
#include <linux/mm.h>
#include <linux/mutex.h>
#include <linux/namei.h>
#include <linux/rcupdate.h>
#include <linux/ratelimit.h>
#include <linux/slab.h>
#include <linux/susfs.h>
#include <linux/susfs_ksu.h>
#include <linux/uaccess.h>
#include <linux/workqueue.h>

struct priority_bitmap {
	DECLARE_BITMAP(bits, SUSFS_PRIORITY_UID_FILTER_UID_NUM);
};

static struct priority_bitmap __rcu *priority_bitmap;
static DEFINE_MUTEX(priority_lock);
static char *priority_packages;
static u64 priority_generation;
static struct path priority_data_root;
static struct path priority_system_root;
static struct fsnotify_group *priority_group;
static atomic_t priority_events = ATOMIC_INIT(0);
static void priority_refresh(struct work_struct *work);
static DECLARE_DELAYED_WORK(priority_work, priority_refresh);

static char *priority_dup(const char *s)
{
	size_t len = strlen(s) + 1;
	char *copy = kvmalloc(len, GFP_KERNEL);

	if (copy)
		memcpy(copy, s, len);
	return copy;
}

static bool priority_valid_package(const char *name)
{
	const char *p;
	size_t len = strlen(name);

	if (!len || len > 255 || !strcmp(name, ".") || !strcmp(name, ".."))
		return false;
	for (p = name; *p; p++) {
		if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
		    (*p >= '0' && *p <= '9') || *p == '.' || *p == '_')
			continue;
		return false;
	}
	return true;
}

/* Caller holds a reference to root and has overridden subjective credentials. */
static int priority_resolve(const struct path *root, const char *name, uid_t *uid)
{
	struct path path;
	struct kstat stat;
	int err;

	err = vfs_path_lookup(root->dentry, root->mnt, name,
			      LOOKUP_FOLLOW | LOOKUP_DIRECTORY, &path);
	if (err)
		return err;
	err = vfs_getattr(&path, &stat, STATX_BASIC_STATS, 0);
	path_put(&path);
	if (err)
		return err;
	*uid = from_kuid(&init_user_ns, stat.uid);
	if (*uid < SUSFS_PRIORITY_UID_FILTER_MIN_UID ||
	    *uid > SUSFS_PRIORITY_UID_FILTER_MAX_UID)
		return -ERANGE;
	return 0;
}

static int priority_parse(char *names, const struct path *root,
			  struct priority_bitmap *bitmap, bool refresh)
{
	const struct cred *saved;
	struct cred *cred = READ_ONCE(ksu_cred);
	char *name;
	uid_t uid;
	int err = 0;

	if (!cred)
		return -EAGAIN;
	saved = override_creds(cred);
	if (!susfs_is_current_ksu_domain()) {
		err = -EACCES;
		goto out;
	}
	while ((name = strsep(&names, ","))) {
		name = strim(name);
		if (!*name)
			continue;
		if (!priority_valid_package(name)) {
			err = -EINVAL;
			break;
		}
		err = priority_resolve(root, name, &uid);
		/*
		 * Missing packages and changed app-id ranges disappear on refresh.
		 * Transient failures must not replace a working filter with zeros.
		 */
		if (refresh && (err == -ENOENT || err == -ENOTDIR || err == -ERANGE)) {
			err = 0;
			continue;
		}
		if (err)
			break;
		set_bit(uid - SUSFS_PRIORITY_UID_FILTER_MIN_UID, bitmap->bits);
	}
out:
	revert_creds(saved);
	return err;
}

static void priority_queue_refresh(unsigned long delay)
{
	atomic_inc(&priority_events);
	mod_delayed_work(system_unbound_wq, &priority_work, delay);
}

/* This callback holds fsnotify SRCU/rename locks: never resolve paths here. */
static SUSFS_DECL_FSNOTIFY_OPS(priority_inode_event)
{
	if (file_name && susfs_fname_len(file_name) == 13 &&
	    !memcmp(susfs_fname_arg(file_name), "packages.list", 13))
		priority_queue_refresh(msecs_to_jiffies(250));
	return 0;
}

static void priority_free_mark(struct fsnotify_mark *mark)
{
	kfree(mark);
}

static const struct fsnotify_ops priority_notify_ops = {
	.handle_event = priority_inode_event,
	.free_mark = priority_free_mark,
};

/* Called outside fsnotify callbacks, with priority_lock held. */
static int priority_watch(const struct path *system)
{
	struct fsnotify_group *group;
	struct fsnotify_mark *mark;
	int err;

	if (priority_group)
		return d_backing_inode(priority_system_root.dentry) ==
		       d_backing_inode(system->dentry) ? 0 : -EXDEV;
	group = fsnotify_alloc_group(&priority_notify_ops);
	if (IS_ERR(group))
		return PTR_ERR(group);
	mark = kzalloc(sizeof(*mark), GFP_KERNEL);
	if (!mark) {
		fsnotify_destroy_group(group);
		return -ENOMEM;
	}
	fsnotify_init_mark(mark, group);
	mark->mask = FS_CREATE | FS_MOVED_TO | FS_CLOSE_WRITE | FS_DELETE |
		     FS_EVENT_ON_CHILD;
	err = fsnotify_add_mark(mark, d_backing_inode(system->dentry), NULL, 0);
	fsnotify_put_mark(mark);
	if (err) {
		fsnotify_destroy_group(group);
		return err;
	}
	priority_system_root = *system;
	path_get(&priority_system_root);
	priority_group = group;
	return 0;
}

static int priority_get_roots(struct path *data, struct path *system)
{
	const struct cred *saved;
	struct cred *cred = READ_ONCE(ksu_cred);
	int err;

	if (!cred)
		return -EAGAIN;
	saved = override_creds(cred);
	if (!susfs_is_current_ksu_domain()) {
		err = -EACCES;
		goto out;
	}
	err = kern_path("/data/data", LOOKUP_FOLLOW | LOOKUP_DIRECTORY, data);
	if (err)
		goto out;
	err = kern_path("/data/system", LOOKUP_FOLLOW | LOOKUP_DIRECTORY, system);
	if (err) {
		path_put(data);
		memset(data, 0, sizeof(*data));
	}
out:
	revert_creds(saved);
	return err;
}

int susfs_set_priority_uid_filter(void __user *arg)
{
	struct st_susfs_priority_uid_filter *info = NULL;
	struct priority_bitmap *bitmap = NULL, *old;
	struct path data = { }, system = { }, old_data;
	char *names = NULL, *old_names;
	int err;

	BUILD_BUG_ON(offsetof(struct st_susfs_priority_uid_filter, err) != 65536);
	BUILD_BUG_ON(sizeof(struct st_susfs_priority_uid_filter) != 65540);
	if (!uid_eq(current_uid(), GLOBAL_ROOT_UID))
		return -EPERM;
	if (!arg)
		return -EFAULT;
	info = kvmalloc(sizeof(*info), GFP_KERNEL);
	if (!info) {
		err = -ENOMEM;
		goto out;
	}
	if (copy_from_user(info, arg, sizeof(*info))) {
		err = -EFAULT;
		goto out;
	}
	if (!memchr(info->app_strings, '\0', sizeof(info->app_strings)) ||
	    !info->app_strings[0]) {
		err = -EINVAL;
		goto out;
	}
	names = priority_dup(info->app_strings);
	bitmap = kzalloc(sizeof(*bitmap), GFP_KERNEL);
	if (!names || !bitmap) {
		err = -ENOMEM;
		goto out;
	}
	err = priority_get_roots(&data, &system);
	if (err)
		goto out;
	err = priority_parse(info->app_strings, &data, bitmap, false);
	if (err)
		goto out;
	mutex_lock(&priority_lock);
	err = priority_watch(&system);
	if (err) {
		mutex_unlock(&priority_lock);
		goto out;
	}
	old = rcu_dereference_protected(priority_bitmap, lockdep_is_held(&priority_lock));
	old_data = priority_data_root;
	old_names = priority_packages;
	priority_data_root = data;
	memset(&data, 0, sizeof(data));
	priority_packages = names;
	names = NULL;
	priority_generation++;
	rcu_assign_pointer(priority_bitmap, bitmap);
	bitmap = NULL;
	mutex_unlock(&priority_lock);
	/* Readers own their RCU section; wait outside all config/fsnotify locks. */
	synchronize_rcu();
	kfree(old);
	kvfree(old_names);
	if (old_data.mnt)
		path_put(&old_data);
	priority_queue_refresh(msecs_to_jiffies(250));
out:
	if (system.mnt)
		path_put(&system);
	if (data.mnt)
		path_put(&data);
	kfree(bitmap);
	kvfree(names);
	kvfree(info);
	/* Preserve the official ksu_susfs payload ABI, including error reporting. */
	if (put_user(err, &((struct st_susfs_priority_uid_filter __user *)arg)->err))
		return -EFAULT;
	return 0;
}

static void priority_refresh(struct work_struct *work)
{
	struct priority_bitmap *bitmap = NULL, *old;
	struct path root;
	char *names;
	u64 generation;
	int event = atomic_read(&priority_events);
	int err;

	mutex_lock(&priority_lock);
	if (!priority_packages) {
		mutex_unlock(&priority_lock);
		return;
	}
	names = priority_dup(priority_packages);
	root = priority_data_root;
	path_get(&root);
	generation = priority_generation;
	mutex_unlock(&priority_lock);
	if (!names) {
		err = -ENOMEM;
		goto out;
	}
	bitmap = kzalloc(sizeof(*bitmap), GFP_KERNEL);
	if (!bitmap) {
		err = -ENOMEM;
		goto out;
	}
	/* Relative to the captured Android path; a kworker may have no fs. */
	err = priority_parse(names, &root, bitmap, true);
	if (err)
		goto out;
	mutex_lock(&priority_lock);
	if (generation != priority_generation || event != atomic_read(&priority_events)) {
		mutex_unlock(&priority_lock);
		err = -EAGAIN;
		goto out;
	}
	old = rcu_dereference_protected(priority_bitmap, lockdep_is_held(&priority_lock));
	rcu_assign_pointer(priority_bitmap, bitmap);
	bitmap = NULL;
	mutex_unlock(&priority_lock);
	synchronize_rcu();
	kfree(old);
out:
	path_put(&root);
	kvfree(names);
	kfree(bitmap);
	if (err) {
		if (err != -EAGAIN)
			pr_warn_ratelimited("susfs: priority UID refresh failed: %d\n", err);
		mod_delayed_work(system_unbound_wq, &priority_work,
				 err == -EAGAIN ? msecs_to_jiffies(250) : 5 * HZ);
	}
}

bool susfs_is_priority_uid_filtered(uid_t uid)
{
	struct priority_bitmap *bitmap;
	uid_t app_id = uid % 100000;
	bool filtered = false;

	if (app_id < SUSFS_PRIORITY_UID_FILTER_MIN_UID ||
	    app_id > SUSFS_PRIORITY_UID_FILTER_MAX_UID)
		return false;
	rcu_read_lock();
	bitmap = rcu_dereference(priority_bitmap);
	if (bitmap)
		filtered = test_bit(app_id - SUSFS_PRIORITY_UID_FILTER_MIN_UID, bitmap->bits);
	rcu_read_unlock();
	return filtered;
}
