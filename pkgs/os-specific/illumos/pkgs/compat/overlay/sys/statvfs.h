/*
 * Same story as <sys/stat.h>: the gate's `struct statvfs` is 136 bytes and
 * glibc's is 112, and the field lists differ outright -- `f_basetype` and
 * `f_fstr` have no glibc counterpart at all.  Redirect the calls so compat can
 * translate what does correspond and be explicit about what does not.
 *
 * As there, it is the unsuffixed names that survive under _LP64, and the
 * macros are function-like so that `struct statvfs` is left alone.
 */
#include_next <sys/statvfs.h>

#ifndef	_ILLUMOS_COMPAT_STATVFS_H
#define	_ILLUMOS_COMPAT_STATVFS_H

extern int __compat_statvfs64(const char *, struct statvfs64 *);
extern int __compat_fstatvfs64(int, struct statvfs64 *);

#define	statvfs64(p, b)	__compat_statvfs64((p), (b))
#define	fstatvfs64(f, b)	__compat_fstatvfs64((f), (b))

#endif	/* _ILLUMOS_COMPAT_STATVFS_H */
