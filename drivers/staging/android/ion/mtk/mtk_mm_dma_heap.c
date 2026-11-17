// SPDX-License-Identifier: GPL-2.0
/*
 * /dev/dma_heap/mtk_mm
 *
 * A DMA-BUF heap that is a thin front end to the MediaTek ION multimedia
 * heap. Userspace that asks libdmabufheap for the "mtk_mm" heap (e.g. the
 * Samsung/MTK build of Skia's SkBufMalloc) gets a buffer allocated by
 * exactly the same allocator the MTK gralloc uses through /dev/ion.
 *
 * The returned dma-buf is the ION exporter's own dma-buf, so every MTK
 * driver that imports ION buffers (ion_import_dma_buf, M4U/IOMMU, camera,
 * display, codecs) keeps working on it unchanged.
 *
 * Buffers are uncached and zero filled. Plain dma-heap clients such as
 * Skia do not call DMA_BUF_IOCTL_SYNC, so an uncached mapping is the only
 * choice that is correct without CPU cache maintenance by the caller.
 */

#define pr_fmt(fmt) "mtk_mm_dma_heap: " fmt

#include <linux/dma-buf.h>
#include <linux/dma-heap.h>
#include <linux/err.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/sysfs.h>
#include <linux/workqueue.h>

#include "ion.h"
#include "ion_drv.h"
#include "mtk_ion.h"

#define MTK_MM_HEAP_NAME "mtk_mm"

static struct ion_client *mtk_mm_client;
static DEFINE_MUTEX(mtk_mm_client_lock);

/*
 * ion_client_create() records current->group_leader as the owner unless
 * that is a kernel thread. We do not want every buffer to be accounted to
 * (and pin the task struct of) whichever process allocated first, so the
 * single shared client is created from a kworker.
 */
static void mtk_mm_client_create_fn(struct work_struct *work)
{
	struct ion_client *client;

	client = ion_client_create(g_ion_device, "dma_heap_mtk_mm");
	if (IS_ERR(client)) {
		pr_err("ion_client_create failed: %ld\n", PTR_ERR(client));
		client = NULL;
	}
	mtk_mm_client = client;
}
static DECLARE_WORK(mtk_mm_client_work, mtk_mm_client_create_fn);

static struct ion_client *mtk_mm_get_client(void)
{
	struct ion_client *client;

	mutex_lock(&mtk_mm_client_lock);
	if (!mtk_mm_client) {
		if (!g_ion_device) {
			mutex_unlock(&mtk_mm_client_lock);
			return ERR_PTR(-ENODEV);
		}
		schedule_work(&mtk_mm_client_work);
		flush_work(&mtk_mm_client_work);
	}
	client = mtk_mm_client ? mtk_mm_client : ERR_PTR(-ENOMEM);
	mutex_unlock(&mtk_mm_client_lock);

	return client;
}

static struct dma_buf *mtk_mm_heap_allocate(struct dma_heap *heap,
					    unsigned long len,
					    unsigned long fd_flags,
					    unsigned long heap_flags)
{
	struct ion_client *client;
	struct ion_handle *handle;
	struct dma_buf *dmabuf;

	client = mtk_mm_get_client();
	if (IS_ERR(client))
		return ERR_CAST(client);

	handle = ion_alloc(client, len, 0, ION_HEAP_MULTIMEDIA_MASK, 0);
	if (IS_ERR(handle))
		return ERR_CAST(handle);

	dmabuf = ion_share_dma_buf(client, handle);

	/*
	 * The dma-buf holds its own reference on the ion buffer. Dropping
	 * the handle leaves the dma-buf as the only owner, so the memory is
	 * released when the last fd/mapping/attachment goes away.
	 */
	ion_free(client, handle);

	return dmabuf;
}

static const struct dma_heap_ops mtk_mm_heap_ops = {
	.allocate = mtk_mm_heap_allocate,
};

/*
 * /sys/kernel/dma_heap/total_pools_kb
 *
 * Same path and meaning as the Android common kernel node that libmeminfo
 * reads: kB of free memory held in heap page pools. The only pooled heap on
 * this kernel is the MTK ION mm heap behind mtk_mm, so report its pools.
 */
static ssize_t total_pools_kb_show(struct kobject *kobj,
				   struct kobj_attribute *attr, char *buf)
{
	return sprintf(buf, "%lu\n", ion_mm_heap_pools_kb());
}

static struct kobj_attribute total_pools_kb_attr = __ATTR_RO(total_pools_kb);

static void mtk_mm_dma_heap_sysfs_init(void)
{
	struct kobject *kobj;

	kobj = kobject_create_and_add("dma_heap", kernel_kobj);
	if (!kobj) {
		pr_warn("cannot create /sys/kernel/dma_heap\n");
		return;
	}
	if (sysfs_create_file(kobj, &total_pools_kb_attr.attr)) {
		pr_warn("cannot create total_pools_kb\n");
		kobject_put(kobj);
	}
}

static int __init mtk_mm_dma_heap_init(void)
{
	struct dma_heap_export_info exp_info;
	struct dma_heap *heap;

	exp_info.name = MTK_MM_HEAP_NAME;
	exp_info.ops = &mtk_mm_heap_ops;
	exp_info.priv = NULL;

	heap = dma_heap_add(&exp_info);
	if (IS_ERR(heap))
		return PTR_ERR(heap);

	mtk_mm_dma_heap_sysfs_init();

	pr_info("registered /dev/dma_heap/%s\n", MTK_MM_HEAP_NAME);
	return 0;
}
/* after the ION platform driver has probed; the ION client is made lazily */
late_initcall_sync(mtk_mm_dma_heap_init);
