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
 * <sys/elf.h> for a consumer that gets its ELF types from the *host's* ELF
 * library rather than from illumos'.
 *
 * On illumos <sys/elf.h> is where the ELF types and constants live, and gate
 * headers include it by that name -- <sys/ctf_api.h> among them.  glibc puts
 * the same definitions in <elf.h> and ships a <sys/elf.h> whose entire
 * content is
 *
 *	#error This header is unsupported on x86-64.
 *
 * so a bare #include of either name fails: the host's because it refuses, and
 * illumos' (which the staged profile alongside this one supplies) because its
 * Elf64_Ehdr and friends then collide, tag for tag, with the ones <elf.h> has
 * already defined -- and <elf.h> is exactly what libelf.h drags in.
 *
 * Hence a third answer, kept apart from the staged profile because the two are
 * mutually exclusive by construction: a consumer wants illumos' ELF types or
 * the host's, never both.  Prepend `compat.hostElfCflags` to reach this one.
 * Compare tools/ctf/native/sys/elf.h upstream, which is the same shim.
 */

#ifndef	_ILLUMOS_COMPAT_HOST_SYS_ELF_H
#define	_ILLUMOS_COMPAT_HOST_SYS_ELF_H

#include <elf.h>

#endif	/* _ILLUMOS_COMPAT_HOST_SYS_ELF_H */
