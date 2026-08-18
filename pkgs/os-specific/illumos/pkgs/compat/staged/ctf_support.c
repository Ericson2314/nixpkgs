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
 * The handful of definitions that a foreign libc, and the objects dropped
 * from the native libconv, would otherwise leave undefined.  Built into
 * libconv, which everything else here links against.
 */

#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <stdarg.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>

/*
 * On illumos this is a .note section plus a string, generated from
 * libconv/common/bld_vernote.ksh by ksh93 and the illumos assembler.  Only
 * the string is ever read (ldmain.c stamps it into .comment, liblddbg prints
 * it), so build it with the C compiler instead.
 */
#ifndef	LINK_VER_STRING
#define	LINK_VER_STRING	"native (illumos)"
#endif
const char link_ver_string[] = LINK_VER_STRING;

/*
 * ASSERT3*()/VERIFY3*() from <sys/debug.h> call this; illumos has it in libc.
 * assfail() itself comes from cmd/sgs/common/assfail.c.
 */
void
assfail3(const char *a, uintmax_t lv, const char *op, uintmax_t rv,
    const char *f, int l)
{
	(void) fprintf(stderr,
	    "assertion failed: %s (0x%jx %s 0x%jx), file: %s, line: %d\n",
	    a, lv, op, rv, f, l);
	abort();
}

/*
 * common/avl calls panic() on an impossible tree state.  In the kernel that
 * is a system panic; here, the same thing an assertion failure does.
 */
void
panic(const char *fmt, ...)
{
	va_list	ap;

	va_start(ap, fmt);
	(void) vfprintf(stderr, fmt, ap);
	va_end(ap);
	(void) fputc('\n', stderr);
	abort();
}

/*
 * ---------------------------------------------------------------------------
 * From tools/ctf/native/native_support.c -- the CTF tools' half of the same
 * job.  `assfail3()` above already covered what the two files shared.
 * ---------------------------------------------------------------------------
 */
/*
 * Declared rather than reached through <errno.h>, which only exposes it under
 * _GNU_SOURCE -- and this file is compiled with the same flags as the rest of
 * libctf, where turning that on would quietly swap strerror_r() and friends
 * for their GNU variants.
 */
extern char *program_invocation_name;

/*
 * ASSERT()/VERIFY() from <sys/debug.h>.  On illumos this lives in libc.
 *
 * Weak, unlike assfail3() above, because cmd/sgs/common/assfail.c has its own
 * and libconv links both that and this file.  A strong definition here would
 * be a duplicate symbol for every sgs consumer; weak lets the one that comes
 * with the sources win and leaves this as the fallback for everyone else.
 */
__attribute__((__weak__))
void
assfail(const char *a, const char *f, int l)
{
	(void) fprintf(stderr, "assertion failed: %s, file: %s, line: %d\n",
	    a, f, l);
	abort();
}

/*
 * getexecname(3C).  tools/ctf/common/utils.c uses it to derive the program
 * name for diagnostics.  glibc's nearest equivalent is program_invocation_name,
 * which is the argv[0] the process was started with rather than the resolved
 * path; that is the same thing for every caller here, and /proc/self/exe is
 * the fallback when it is unset.
 */
const char *
getexecname(void)
{
	static char path[PATH_MAX];
	ssize_t n;

	if (program_invocation_name != NULL && *program_invocation_name != '\0')
		return (program_invocation_name);

	n = readlink("/proc/self/exe", path, sizeof (path) - 1);
	if (n < 0)
		return (NULL);
	path[n] = '\0';

	return (path);
}

/*
 * strtonum(3C), which illumos took from OpenBSD.  ctfconvert(1) uses it to
 * parse -b/-j.  This is the documented behaviour: on success the value is
 * returned and *errstrp is set to NULL; on failure 0 is returned and *errstrp
 * names the problem, with errno set to EINVAL or ERANGE.
 */
long long
strtonum(const char *numstr, long long minval, long long maxval,
    const char **errstrp)
{
	const char *errstr = NULL;
	long long val = 0;
	char *end;
	int saved_errno = errno;

	if (minval > maxval) {
		errstr = "invalid";
		errno = EINVAL;
		goto out;
	}

	errno = 0;
	val = strtoll(numstr, &end, 10);
	if (end == numstr || *end != '\0') {
		errstr = "invalid";
		errno = EINVAL;
		val = 0;
	} else if ((val == LLONG_MIN && errno == ERANGE) || val < minval) {
		errstr = "too small";
		errno = ERANGE;
		val = 0;
	} else if ((val == LLONG_MAX && errno == ERANGE) || val > maxval) {
		errstr = "too large";
		errno = ERANGE;
		val = 0;
	}

out:
	if (errstrp != NULL)
		*errstrp = errstr;
	if (errstr == NULL)
		errno = saved_errno;

	return (val);
}

