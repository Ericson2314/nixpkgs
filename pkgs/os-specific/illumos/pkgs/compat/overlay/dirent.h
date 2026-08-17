/*
 * `struct dirent` is not the same on both sides: glibc's carries a d_type byte
 * that illumos' does not, so d_name sits one byte further along. A gate-built
 * caller reading a host readdir(3C) result therefore sees every name shifted
 * by one -- the first entry of a directory comes back as "." with the leading
 * character eaten, and nothing matches.
 *
 * Same treatment as <sys/stat.h>: let the gate's header declare everything,
 * then redirect the calls to compat, which reads with the host's layout and
 * returns the gate's. `DIR` is passed straight through as the host's, which is
 * safe because it is opaque by contract -- nothing outside libc may look
 * inside one.
 *
 * Function-like macros, so that `struct dirent` and `DIR` are left alone.
 */
#include_next <dirent.h>

#ifndef	_ILLUMOS_COMPAT_DIRENT_H
#define	_ILLUMOS_COMPAT_DIRENT_H

extern DIR *__compat_opendir(const char *);
extern struct dirent *__compat_readdir(DIR *);
extern int __compat_closedir(DIR *);

#define	opendir(p)	__compat_opendir(p)
#define	readdir(d)	__compat_readdir(d)
#define	closedir(d)	__compat_closedir(d)

#endif	/* _ILLUMOS_COMPAT_DIRENT_H */
