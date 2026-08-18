/*
 * libcompat, host half: the pieces that must see the *host's* <unistd.h> and
 * <errno.h> in order to forward to them.  Nothing in this file may include a
 * gate header -- the whole point is that it sits on the other side of the
 * boundary from compat_gate.c.
 */
#include <errno.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>

/*
 * Under _REENTRANT the gate's <errno.h> resolves `errno` to `*___errno()`.
 * glibc spells the same thing __errno_location().  Both return a pointer to
 * the calling thread's errno, so this is an exact correspondence, not an
 * approximation.
 */
int *
___errno(void)
{
	return (__errno_location());
}

/*
 * The gate's <sys/param.h> reaches sysconf(3C) through the private `_sysconf`
 * entry point -- PAGESIZE is `(_sysconf(_SC_PAGESIZE))`.
 *
 * The _SC_* numbers are part of the illumos ABI and do not match the host's,
 * so this cannot simply be an alias for sysconf(3): the numbers have to be
 * translated.  Only the ones actually reachable are handled, and anything
 * else aborts rather than returning a plausible-looking wrong answer -- a
 * silently mistranslated PAGESIZE would corrupt a filesystem image in a way
 * that would be very hard to trace back here.
 */
#define	ILLUMOS_SC_CLK_TCK	3	/* <sys/unistd.h> */
#define	ILLUMOS_SC_PAGESIZE	11

long
_sysconf(int name)
{
	switch (name) {
	case ILLUMOS_SC_CLK_TCK:
		return (sysconf(_SC_CLK_TCK));
	case ILLUMOS_SC_PAGESIZE:
		return (sysconf(_SC_PAGESIZE));
	default:
		(void) fprintf(stderr,
		    "illumos libcompat: _sysconf(%d) is not translated; "
		    "add it to compat_host.c\n", name);
		abort();
	}
}

/*
 * stat(2) and statvfs(2), host side.
 *
 * These read the host's structs and copy the fields out into the neutral
 * layout in compat_priv.h.  The gate half then writes them into the gate's
 * structs.  Going through a third representation is what keeps the two
 * incompatible definitions of `struct stat64` out of the same translation
 * unit.
 */
#include <sys/stat.h>
#include <sys/statvfs.h>
#include "compat_priv.h"

static void
fill_stat(const struct stat64 *st, struct compat_stat *cs)
{
	cs->cs_dev = st->st_dev;
	cs->cs_ino = st->st_ino;
	cs->cs_rdev = st->st_rdev;
	cs->cs_mode = st->st_mode;
	cs->cs_nlink = st->st_nlink;
	cs->cs_uid = st->st_uid;
	cs->cs_gid = st->st_gid;
	cs->cs_size = st->st_size;
	cs->cs_blksize = st->st_blksize;
	cs->cs_blocks = st->st_blocks;
	cs->cs_atime = st->st_atime;
	cs->cs_mtime = st->st_mtime;
	cs->cs_ctime = st->st_ctime;
}

int
__compat_host_stat(const char *path, struct compat_stat *cs)
{
	struct stat64 st;

	if (stat64(path, &st) == -1)
		return (-1);
	fill_stat(&st, cs);
	return (0);
}

int
__compat_host_lstat(const char *path, struct compat_stat *cs)
{
	struct stat64 st;

	if (lstat64(path, &st) == -1)
		return (-1);
	fill_stat(&st, cs);
	return (0);
}

int
__compat_host_fstat(int fd, struct compat_stat *cs)
{
	struct stat64 st;

	if (fstat64(fd, &st) == -1)
		return (-1);
	fill_stat(&st, cs);
	return (0);
}

static void
fill_statvfs(const struct statvfs64 *sv, struct compat_statvfs *cv)
{
	cv->cv_bsize = sv->f_bsize;
	cv->cv_frsize = sv->f_frsize;
	cv->cv_blocks = sv->f_blocks;
	cv->cv_bfree = sv->f_bfree;
	cv->cv_bavail = sv->f_bavail;
	cv->cv_files = sv->f_files;
	cv->cv_ffree = sv->f_ffree;
	cv->cv_favail = sv->f_favail;
	cv->cv_fsid = sv->f_fsid;
	cv->cv_flag = sv->f_flag;
	cv->cv_namemax = sv->f_namemax;
}

int
__compat_host_statvfs(const char *path, struct compat_statvfs *cv)
{
	struct statvfs64 sv;

	if (statvfs64(path, &sv) == -1)
		return (-1);
	fill_statvfs(&sv, cv);
	return (0);
}

int
__compat_host_fstatvfs(int fd, struct compat_statvfs *cv)
{
	struct statvfs64 sv;

	if (fstatvfs64(fd, &sv) == -1)
		return (-1);
	fill_statvfs(&sv, cv);
	return (0);
}

/*
 * Directory reading, host side. The host's DIR is handed back as an opaque
 * void *; only this file ever dereferences it.
 */
#include <dirent.h>

void *
__compat_host_opendir(const char *path)
{
	return ((void *)opendir(path));
}

int
__compat_host_readdir(void *dirp, struct compat_dirent *out)
{
	struct dirent *de;

	errno = 0;
	de = readdir((DIR *)dirp);
	if (de == NULL)
		return (errno == 0 ? 0 : -1);

	out->cd_ino = (uint64_t)de->d_ino;
	(void) snprintf(out->cd_name, sizeof (out->cd_name), "%s", de->d_name);
	return (1);
}

int
__compat_host_closedir(void *dirp)
{
	return (closedir((DIR *)dirp));
}

/*
 * strtonum(3C) / strtonumx(3C).
 *
 * Originally OpenBSD's, and part of illumos' libc
 * (lib/libc/port/gen/strtonum.c); glibc has no equivalent.  ctfconvert(1)
 * parses its -j and -m arguments with it, and that one missing symbol is all
 * that stands between the gate's own cmd/ctfconvert/ctfconvert.c and a
 * build-host binary -- which is why it is filled in here rather than by
 * patching the gate.
 *
 * The error strings and the errno left behind on each failure are part of the
 * documented interface, so they are reproduced exactly rather than
 * approximated.
 */
#include <limits.h>

#define	COMPAT_STRTONUM_INVALID		1
#define	COMPAT_STRTONUM_TOOSMALL	2
#define	COMPAT_STRTONUM_TOOLARGE	3
#define	COMPAT_STRTONUM_BADBASE		4

/* The largest base strtoll(3C) accepts: digits plus the 26 letters. */
#define	COMPAT_STRTONUM_MBASE		('z' - 'a' + 1 + 10)

long long
strtonumx(const char *numstr, long long minval, long long maxval,
    const char **errstrp, int base)
{
	long long ll = 0;
	int error = 0;
	char *ep;
	struct errval {
		const char *errstr;
		int err;
	} ev[5] = {
		{ NULL,		0 },
		{ "invalid",	EINVAL },
		{ "too small",	ERANGE },
		{ "too large",	ERANGE },
		{ "unparsable; invalid base specified", EINVAL },
	};

	ev[0].err = errno;
	errno = 0;
	if (minval > maxval) {
		error = COMPAT_STRTONUM_INVALID;
	} else if (base < 0 || base > COMPAT_STRTONUM_MBASE || base == 1) {
		error = COMPAT_STRTONUM_BADBASE;
	} else {
		ll = strtoll(numstr, &ep, base);
		if (numstr == ep || *ep != '\0')
			error = COMPAT_STRTONUM_INVALID;
		else if ((ll == LLONG_MIN && errno == ERANGE) || ll < minval)
			error = COMPAT_STRTONUM_TOOSMALL;
		else if ((ll == LLONG_MAX && errno == ERANGE) || ll > maxval)
			error = COMPAT_STRTONUM_TOOLARGE;
	}
	if (errstrp != NULL)
		*errstrp = ev[error].errstr;
	errno = ev[error].err;
	if (error != 0)
		ll = 0;

	return (ll);
}

long long
strtonum(const char *numstr, long long minval, long long maxval,
    const char **errstrp)
{
	return (strtonumx(numstr, minval, maxval, errstrp, 10));
}
