/*
 * `struct stat` is an ABI, and it is not the same ABI on two systems: the
 * gate's is 128 bytes where glibc's is 144.  Letting the gate's declaration
 * meet the host's implementation therefore does not merely give wrong field
 * values, it overruns the caller's buffer by 16 bytes -- which in practice
 * smashes the return address of whatever function declared the struct on its
 * stack.
 *
 * So these cannot be forwarded the way the stdio streams are.  Let the gate's
 * header declare the struct and the functions as usual, then redirect the
 * *calls* to compat entry points that fill the gate's layout field by field
 * from the host's.  The gate's `struct stat` stays the one every caller sees,
 * which is what keeps S_ISREG() and friends working.
 *
 * Note which names are redirected.  Under _LP64 the gate's <sys/stat.h> maps
 * the transitional large-file spellings onto the plain ones --
 *
 *	#define stat64 stat
 *	#define fstat64 fstat
 *
 * -- so by the time a call reaches here it is spelled `stat`, whatever the
 * caller wrote.  Redirecting `stat64` instead would be worse than useless: it
 * would override the gate's mapping and leave `struct stat64` an undefined
 * type.  (An ILP32 build keeps the two families distinct and would need both
 * sets; nothing here builds ILP32.)
 *
 * The redirection has to be a macro rather than a definition of `stat`
 * itself, because compat's host half has to call the host's `stat`: if compat
 * defined that name the call would resolve back into compat and recurse.
 * And it has to be *function-like*, since an object-like `#define stat ...`
 * would rewrite every mention of `struct stat` too, including the ones in
 * these very declarations.
 */
#include_next <sys/stat.h>

#ifndef	_ILLUMOS_COMPAT_STAT_H
#define	_ILLUMOS_COMPAT_STAT_H

extern int __compat_stat64(const char *, struct stat64 *);
extern int __compat_lstat64(const char *, struct stat64 *);
extern int __compat_fstat64(int, struct stat64 *);

#define	stat64(p, b)	__compat_stat64((p), (b))
#define	lstat64(p, b)	__compat_lstat64((p), (b))
#define	fstat64(f, b)	__compat_fstat64((f), (b))

#endif	/* _ILLUMOS_COMPAT_STAT_H */
