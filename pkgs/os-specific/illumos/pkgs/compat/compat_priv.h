/*
 * The interface between libcompat's two halves.
 *
 * compat_host.c is compiled against the host's headers and compat_gate.c
 * against the gate's, precisely because the two disagree about layouts.  That
 * means nothing declared here may mention a type either libc defines: this
 * header is plain fixed-width integers only, so that both halves agree on it
 * by construction.
 */
#ifndef	_ILLUMOS_COMPAT_PRIV_H
#define	_ILLUMOS_COMPAT_PRIV_H

#include <stdint.h>

struct compat_stat {
	uint64_t	cs_dev;
	uint64_t	cs_ino;
	uint64_t	cs_rdev;
	uint32_t	cs_mode;
	uint32_t	cs_nlink;
	uint32_t	cs_uid;
	uint32_t	cs_gid;
	int64_t		cs_size;
	int64_t		cs_blksize;
	int64_t		cs_blocks;
	int64_t		cs_atime;
	int64_t		cs_mtime;
	int64_t		cs_ctime;
};

struct compat_statvfs {
	uint64_t	cv_bsize;
	uint64_t	cv_frsize;
	uint64_t	cv_blocks;
	uint64_t	cv_bfree;
	uint64_t	cv_bavail;
	uint64_t	cv_files;
	uint64_t	cv_ffree;
	uint64_t	cv_favail;
	uint64_t	cv_fsid;
	uint64_t	cv_flag;
	uint64_t	cv_namemax;
};

/*
 * The file-type bits of st_mode (S_IFMT and its values) are identical on both
 * systems, so cs_mode is passed through unmodified and S_ISREG() and friends
 * work on either side.
 */
extern int __compat_host_stat(const char *, struct compat_stat *);
extern int __compat_host_lstat(const char *, struct compat_stat *);
extern int __compat_host_fstat(int, struct compat_stat *);
extern int __compat_host_statvfs(const char *, struct compat_statvfs *);
extern int __compat_host_fstatvfs(int, struct compat_statvfs *);

/*
 * Directory reading. `struct dirent` is another layout the two systems do not
 * share: glibc carries a d_type byte that illumos does not, so d_name sits one
 * byte further along and every name comes back shifted.
 *
 * The host DIR is passed around as an opaque void * -- neither side may look
 * inside the other's.
 */
struct compat_dirent {
	uint64_t	cd_ino;
	char		cd_name[1024];
};

extern void *__compat_host_opendir(const char *);
/* 1 = an entry, 0 = end of directory, -1 = error. */
extern int __compat_host_readdir(void *, struct compat_dirent *);
extern int __compat_host_closedir(void *);

#endif	/* _ILLUMOS_COMPAT_PRIV_H */
