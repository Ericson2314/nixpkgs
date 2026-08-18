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
 * illumos' <thread.h> over POSIX threads, for the native build of the CTF
 * tools.
 *
 * Using illumos' own <thread.h> is not an option: it reaches <synch.h>,
 * <sys/machlock.h>, <sys/time_impl.h> and <sys/int_types.h>, i.e. the whole
 * illumos type system, which then collides head-on with the host libc's.  The
 * CTF tools' use of the Solaris threads API is confined to lib/mergeq/workq.c
 * -- create N workers, join them -- and maps onto pthreads directly.
 */

#ifndef	_CTF_NATIVE_THREAD_H
#define	_CTF_NATIVE_THREAD_H

#include <pthread.h>
#include <synch.h>
#include <errno.h>

#ifdef	__cplusplus
extern "C" {
#endif

typedef pthread_t	thread_t;
typedef pthread_key_t	thread_key_t;

#define	THR_BOUND	0x00000001
#define	THR_DETACHED	0x00000040

/*
 * illumos' thr_create() takes a stack address and size up front and returns
 * the new thread's id through its last argument.  workq.c passes NULL/0 for
 * the stack and 0 for the flags, which is "give me the defaults" in both
 * spellings, so the shim only has to handle that case honestly: a non-default
 * request is refused rather than silently ignored.
 */
static inline int
thr_create(void *stack_base, size_t stack_size, void *(*start)(void *),
    void *arg, long flags, thread_t *new_thread)
{
	if (stack_base != NULL || stack_size != 0 || flags != 0)
		return (EINVAL);

	return (pthread_create(new_thread, NULL, start, arg));
}

/*
 * illumos' thr_join() can wait for "any thread" when passed 0, and reports
 * which one it reaped through its second argument.  workq.c always names a
 * thread and does not ask, which is exactly pthread_join().
 */
static inline int
thr_join(thread_t wait_for, thread_t *departed, void **status)
{
	if (wait_for == 0)
		return (EINVAL);
	if (departed != NULL)
		*departed = wait_for;

	return (pthread_join(wait_for, status));
}

static inline thread_t
thr_self(void)
{
	return (pthread_self());
}

#ifdef	__cplusplus
}
#endif

#endif	/* _CTF_NATIVE_THREAD_H */
