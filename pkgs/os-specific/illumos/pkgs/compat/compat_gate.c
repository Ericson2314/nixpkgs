/*
 * libcompat, gate half: illumos entry points a foreign libc does not have,
 * implemented against the gate's own headers so that the types in the
 * signatures (aio_result_t, struct extvtoc, ...) are the real ones.
 *
 * The host's libc still supplies the implementation underneath -- pwrite(2),
 * lseek64(2) and friends are spelled the same on both sides, so calling them
 * from here needs nothing special.
 */
#include <sys/types.h>
#include <sys/asynch.h>
#include <sys/time.h>
#include <sys/vtoc.h>
#include <sys/efi_partition.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * llseek(2).  glibc calls the same system call lseek64(2).
 */
offset_t
llseek(int fd, offset_t off, int whence)
{
	return (lseek64(fd, off, whence));
}

/*
 * getfullblkname(3ADM) maps a raw-device path to its block-device peer,
 * /dev/rdsk/c0t0d0s0 -> /dev/dsk/c0t0d0s0.  A foreign host has no such
 * namespace at all, and its callers here are pointed at a regular file, for
 * which illumos itself returns NULL.  So NULL is the honest answer rather
 * than a degraded one -- callers already handle it, since a plain file has no
 * block-device peer on illumos either.
 */
char *
getfullblkname(char *cp)
{
	(void) cp;
	return (NULL);
}

/*
 * fsgetmaxphys(3) asks the kernel for its maximum single-transfer size.  That
 * is a property of the running illumos kernel, which by construction is not
 * the one we are on.  Report failure so the caller falls back to its own
 * default; mkfs treats that as an ordinary, non-fatal outcome.
 */
int
fsgetmaxphys(int *maxphys, int *error)
{
	(void) maxphys;
	*error = ENOTSUP;
	return (0);
}

/*
 * Partition-table readers.  Both only ever describe a real disk; when the
 * target is a regular file there is no label to read, which is exactly the
 * case these stubs report.  Returning failure is faithful rather than
 * degraded -- illumos returns the same for a file.
 */
int
efi_alloc_and_read(int fd, struct dk_gpt **vtoc)
{
	(void) fd;
	*vtoc = NULL;
	return (VT_ERROR);
}

void
efi_free(struct dk_gpt *ptr)
{
	(void) ptr;
}

int
read_extvtoc(int fd, struct extvtoc *vtoc)
{
	(void) fd;
	(void) vtoc;
	return (VT_ERROR);
}

/*
 * aiowrite(3AIO)/aiowait(3AIO), done synchronously.
 *
 * The contract the callers rely on is narrow: aiowrite() queues a write and
 * reports completion through `resultp`, and aiowait() hands back the
 * `aio_result_t *` of some completed request, or (aio_result_t *)-1 with
 * EINVAL when nothing is outstanding.  Callers identify the transaction by
 * casting the returned pointer back to their own struct, so aiowait() must
 * return the identical pointer it was given.
 *
 * Performing the write immediately and queueing the already-complete result
 * satisfies all of that.  It gives up the overlap that makes aio worthwhile
 * on a real system, which costs image-build throughput and nothing else: the
 * bytes written, their order as observed through the fd, and the values
 * reported in aio_return/aio_errno are identical either way.
 */
#define	COMPAT_AIO_MAX	1024

static aio_result_t	*aio_queue[COMPAT_AIO_MAX];
static int		aio_head, aio_count;

int
aiowrite(int fd, caddr_t buf, int bufsz, off_t offset, int whence,
    aio_result_t *resultp)
{
	off_t	off;
	ssize_t	n;

	if (aio_count == COMPAT_AIO_MAX) {
		errno = EAGAIN;
		return (-1);
	}

	/*
	 * pwrite(2) is always absolute, so a SEEK_CUR/SEEK_END request has to
	 * be resolved against the descriptor first.  mkfs only ever uses
	 * SEEK_SET, but resolving the others keeps this honest for the next
	 * caller.
	 */
	if (whence == SEEK_SET) {
		off = offset;
	} else {
		off = lseek(fd, offset, whence);
		if (off == (off_t)-1) {
			resultp->aio_return = -1;
			resultp->aio_errno = errno;
			goto queued;
		}
	}

	n = pwrite(fd, buf, (size_t)bufsz, off);
	resultp->aio_return = (int)n;
	resultp->aio_errno = (n == -1) ? errno : 0;

queued:
	aio_queue[(aio_head + aio_count) % COMPAT_AIO_MAX] = resultp;
	aio_count++;
	return (0);
}

aio_result_t *
aiowait(struct timeval *timeout)
{
	aio_result_t	*resultp;

	(void) timeout;		/* every queued request is already complete */

	if (aio_count == 0) {
		errno = EINVAL;
		return ((aio_result_t *)-1);
	}

	resultp = aio_queue[aio_head];
	aio_head = (aio_head + 1) % COMPAT_AIO_MAX;
	aio_count--;
	return (resultp);
}

/*
 * stat(2) and statvfs(2), gate side.
 *
 * <sys/stat.h> and <sys/statvfs.h> in compat's overlay redirect the gate's
 * calls here.  Each of these fills the *gate's* struct, so every caller keeps
 * seeing the layout its own headers describe -- including the S_IS*() macros,
 * which work because the S_IFMT encoding is common to both systems.
 */
#include <sys/stat.h>
#include <sys/statvfs.h>
#include "compat_priv.h"

static void
to_gate_stat(const struct compat_stat *cs, struct stat64 *sb)
{
	(void) memset(sb, 0, sizeof (*sb));
	sb->st_dev = cs->cs_dev;
	sb->st_ino = cs->cs_ino;
	sb->st_rdev = cs->cs_rdev;
	sb->st_mode = cs->cs_mode;
	sb->st_nlink = cs->cs_nlink;
	sb->st_uid = cs->cs_uid;
	sb->st_gid = cs->cs_gid;
	sb->st_size = cs->cs_size;
	sb->st_blksize = cs->cs_blksize;
	sb->st_blocks = cs->cs_blocks;
	sb->st_atim.tv_sec = cs->cs_atime;
	sb->st_mtim.tv_sec = cs->cs_mtime;
	sb->st_ctim.tv_sec = cs->cs_ctime;
}

int
__compat_stat64(const char *path, struct stat64 *sb)
{
	struct compat_stat cs;

	if (__compat_host_stat(path, &cs) == -1)
		return (-1);
	to_gate_stat(&cs, sb);
	return (0);
}

int
__compat_lstat64(const char *path, struct stat64 *sb)
{
	struct compat_stat cs;

	if (__compat_host_lstat(path, &cs) == -1)
		return (-1);
	to_gate_stat(&cs, sb);
	return (0);
}

int
__compat_fstat64(int fd, struct stat64 *sb)
{
	struct compat_stat cs;

	if (__compat_host_fstat(fd, &cs) == -1)
		return (-1);
	to_gate_stat(&cs, sb);
	return (0);
}

/*
 * f_basetype and f_fstr have no host counterpart -- they name an illumos
 * filesystem type, which the host cannot supply an illumos-meaningful answer
 * for.  They are left empty rather than guessed at: a caller comparing
 * f_basetype against MNTTYPE_UFS should see "no match" rather than a
 * fabricated one.
 */
static void
to_gate_statvfs(const struct compat_statvfs *cv, struct statvfs64 *sv)
{
	(void) memset(sv, 0, sizeof (*sv));
	sv->f_bsize = cv->cv_bsize;
	sv->f_frsize = cv->cv_frsize;
	sv->f_blocks = cv->cv_blocks;
	sv->f_bfree = cv->cv_bfree;
	sv->f_bavail = cv->cv_bavail;
	sv->f_files = cv->cv_files;
	sv->f_ffree = cv->cv_ffree;
	sv->f_favail = cv->cv_favail;
	sv->f_fsid = cv->cv_fsid;
	sv->f_flag = cv->cv_flag;
	sv->f_namemax = cv->cv_namemax;
	sv->f_basetype[0] = '\0';
	sv->f_fstr[0] = '\0';
}

int
__compat_statvfs64(const char *path, struct statvfs64 *sv)
{
	struct compat_statvfs cv;

	if (__compat_host_statvfs(path, &cv) == -1)
		return (-1);
	to_gate_statvfs(&cv, sv);
	return (0);
}

int
__compat_fstatvfs64(int fd, struct statvfs64 *sv)
{
	struct compat_statvfs cv;

	if (__compat_host_fstatvfs(fd, &cv) == -1)
		return (-1);
	to_gate_statvfs(&cv, sv);
	return (0);
}

/*
 * Directory reading, gate side.
 *
 * <dirent.h> in compat's overlay redirects opendir/readdir/closedir here.
 * `DIR` stays opaque -- it is the host's, passed straight through -- while the
 * `struct dirent` handed back is the gate's, so callers see the layout their
 * own headers describe.
 */
#include <dirent.h>

DIR *
__compat_opendir(const char *path)
{
	return ((DIR *)__compat_host_opendir(path));
}

struct dirent *
__compat_readdir(DIR *dirp)
{
	/*
	 * readdir(3C) returns a pointer to storage it owns and which the next
	 * call may reuse, so one static buffer per process matches the
	 * contract. The gate's `struct dirent` ends in a one-byte d_name, so
	 * the trailing space is what actually holds the name.
	 */
	static union {
		struct dirent	de;
		char		space[sizeof (struct dirent) + 1024];
	} buf;
	struct compat_dirent cd;

	if (__compat_host_readdir((void *)dirp, &cd) != 1)
		return (NULL);

	buf.de.d_ino = (ino_t)cd.cd_ino;
	buf.de.d_off = 0;
	(void) strlcpy(buf.de.d_name, cd.cd_name,
	    sizeof (buf.space) - offsetof(struct dirent, d_name));
	buf.de.d_reclen = (ushort_t)(offsetof(struct dirent, d_name) +
	    strlen(buf.de.d_name) + 1);

	return (&buf.de);
}

int
__compat_closedir(DIR *dirp)
{
	return (__compat_host_closedir((void *)dirp));
}
