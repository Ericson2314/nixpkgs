/*
 * This file and its contents are supplied under the terms of the
 * Common Development and Distribution License ("CDDL"), version 1.0.
 * You may only use this file in accordance with the terms of version
 * 1.0 of the CDDL.
 *
 * A full copy of the text of the CDDL should have accompanied this
 * source.  A copy of the CDDL is also available via the Internet at
 * http://www.illumos.org/license/CDDL.
 */

/*
 * Compatibility shims for building the small onbld ELF tools -- elfextract,
 * mbh_patch, vtfontcvt -- on a host whose libc is not illumos'.
 * Force-included (via -include), so it must be safe to include before
 * anything else.
 *
 * The staged headers alongside this file are illumos' own, and they expect
 * illumos' <sys/types.h> to have already supplied the "_t" spellings of the
 * base integer types; a foreign libc supplies none of it.  Nothing here is
 * illumos-specific behaviour, it is purely the vocabulary those headers
 * assume.  Compare tools/sgs/native/native_compat.h and
 * tools/ctf/native/native_compat.h, which do the same job for the native
 * link-editor and the CTF tools.
 */

#ifndef	_ONBLD_NATIVE_COMPAT_H
#define	_ONBLD_NATIVE_COMPAT_H

/*
 * On illumos every sys header reaches <sys/isa_defs.h> by way of
 * <sys/param.h>.  Here <sys/param.h> is the host's, so the staged illumos
 * headers would never see _BIT_FIELDS_LTOH, _LP64 and friends.  Pull it in up
 * front instead.  <sys/ccompile.h> likewise supplies __GNU_INLINE and the
 * __sun_attr__ family, which on illumos arrive via <sys/types.h>.
 */
#include <sys/isa_defs.h>
#include <sys/ccompile.h>

#include <stddef.h>
#include <stdint.h>
#include <sys/types.h>
/*
 * illumos' <strings.h> pulls in <string.h>; the host's does not.
 */
#include <string.h>
#include <strings.h>

#ifdef	__cplusplus
extern "C" {
#endif

#ifndef	_BOOLEAN_T
#define	_BOOLEAN_T
typedef enum { B_FALSE, B_TRUE } boolean_t;
#endif

typedef unsigned char		uchar_t;
typedef unsigned short		ushort_t;
typedef unsigned int		uint_t;
typedef unsigned long		ulong_t;
typedef long long		longlong_t;
typedef unsigned long long	u_longlong_t;

/*
 * illumos' <sys/int_types.h> announces the availability of 64-bit integer
 * types this way.  We do not stage that header -- it redefines the whole
 * intN_t family and would collide with the host's <stdint.h> -- so state the
 * fact directly.
 */
#ifndef	_INT64_TYPE
#define	_INT64_TYPE
#endif
#ifndef	_LONGLONG_TYPE
#define	_LONGLONG_TYPE
#endif

/*
 * illumos' <sys/sysmacros.h> carries these; the host's has only the
 * major/minor/makedev trio, so a bare #include silently loses them.
 * mbh_patch.c uses P2ROUNDUP.
 */
#ifndef	MAX
#define	MAX(a, b)	((a) < (b) ? (b) : (a))
#endif
#ifndef	MIN
#define	MIN(a, b)	((a) > (b) ? (b) : (a))
#endif
#ifndef	howmany
#define	howmany(x, y)	(((x) + ((y) - 1)) / (y))
#endif
#ifndef	roundup
#define	roundup(x, y)	((((x) + ((y) - 1)) / (y)) * (y))
#endif
#ifndef	P2ROUNDUP
#define	P2ROUNDUP(x, align)	(-(-(x) & -(align)))
#endif
#ifndef	P2PHASE
#define	P2PHASE(x, align)	((x) & ((align) - 1))
#endif
#ifndef	P2ALIGN
#define	P2ALIGN(x, align)	((x) & -(align))
#endif
#ifndef	IS_P2ALIGNED
#define	IS_P2ALIGNED(v, a)	((((uintptr_t)(v)) & ((uintptr_t)(a) - 1)) == 0)
#endif
/* Used by common/lz4/lz4.c, which vtfontcvt links in. */
#ifndef	__DECONST
#define	__DECONST(type, var)	((type)(uintptr_t)(const void *)(var))
#endif

/*
 * ARRAY_SIZE is illumos' <sys/sysmacros.h>, which the staged profile does not
 * layer in: it is a kernel-flavoured header whose other contents collide with
 * the host's.  common/ctf/ctf_types.c reaches it through <sys/debug.h> on
 * illumos and finds nothing here.  Same definition, and the same thing
 * tools/ctf/common/ctf_headers.h did for the build over there.
 */
#ifndef	ARRAY_SIZE
#define	ARRAY_SIZE(x)	(sizeof (x) / sizeof (x[0]))
#endif

/*
 * strtonum(3C) is illumos libc, not the host's; libcompat supplies the
 * implementation (compat_host.c) and this is its declaration. Not reached
 * through the gate's <stdlib.h> because the staged profile deliberately lets
 * the host's win.
 */
extern long long strtonum(const char *, long long, long long, const char **);
extern long long strtonumx(const char *, long long, long long, const char **,
    int);


/*
 * The remainder is ported verbatim from the gate's own
 * usr/src/tools/libcompat/common/native_compat.h, which is the merged
 * (sgs + ctf) shim.  This copy had only ever carried what the CTF tools
 * needed, so building anything from cmd/sgs against it failed -- sgsmsg on
 * NL_MSGMAX, and libconv would follow.  Keep the two in step: the gate's is
 * the superset and the one to copy from.
 */

/*
 * illumos' <sys/param.h> exposes the runtime page size as PAGESIZE.
 */
#ifndef	PAGESIZE
#include <unistd.h>
#define	PAGESIZE	((size_t)sysconf(_SC_PAGESIZE))
#endif

/*
 * From illumos' <sys/time.h>.
 */
#ifndef	SEC
#define	SEC		1
#endif
#ifndef	MILLISEC
#define	MILLISEC	1000
#endif
#ifndef	MICROSEC
#define	MICROSEC	1000000
#endif
#ifndef	NANOSEC
#define	NANOSEC		1000000000
#endif

/*
 * From illumos' <limits.h>; the host's has no notion of message catalogues.
 */
#ifndef	NL_MSGMAX
#define	NL_MSGMAX	32767
#endif
#ifndef	NL_SETMAX
#define	NL_SETMAX	255
#endif
#ifndef	NL_TEXTMAX
#define	NL_TEXTMAX	2048
#endif

/*
 * From illumos' <sys/sysmacros.h> and <sys/time.h>.
 */
#ifndef	P2NPHASE
#define	P2NPHASE(x, align)	(-(x) & ((align) - 1))
#endif
#ifndef	ABS
#define	ABS(a)		((a) < 0 ? -(a) : (a))
#endif
#ifdef	__cplusplus
}
#endif

#endif	/* _ONBLD_NATIVE_COMPAT_H */
