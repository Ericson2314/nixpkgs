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
 * illumos' <synch.h> over POSIX threads, for the native build of the CTF
 * tools.  See the comment in thread.h for why this is a shim rather than the
 * real header.
 */

#ifndef	_CTF_NATIVE_SYNCH_H
#define	_CTF_NATIVE_SYNCH_H

#include <pthread.h>
#include <stdlib.h>
#include <errno.h>

#ifdef	__cplusplus
extern "C" {
#endif

typedef pthread_mutex_t		mutex_t;
typedef pthread_rwlock_t	rwlock_t;
typedef pthread_cond_t		cond_t;

#define	DEFAULTMUTEX	PTHREAD_MUTEX_INITIALIZER
#define	DEFAULTRWLOCK	PTHREAD_RWLOCK_INITIALIZER
#define	DEFAULTCV	PTHREAD_COND_INITIALIZER

#define	USYNC_THREAD	0
#define	USYNC_PROCESS	1

/*
 * The lock "types" illumos ORs into the mutex_init() type argument.  Only
 * LOCK_ERRORCHECK is used here (lib/mergeq/mergeq.c), and it has a direct
 * pthread equivalent.
 */
#define	LOCK_NORMAL		0x0
#define	LOCK_ERRORCHECK		0x2
#define	LOCK_RECURSIVE		0x4

/*
 * illumos' ERRORCHECKMUTEX is a statically initialised mutex of type
 * LOCK_ERRORCHECK; PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP is the same thing
 * on glibc.
 */
#ifdef	PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP
#define	ERRORCHECKMUTEX	PTHREAD_ERRORCHECK_MUTEX_INITIALIZER_NP
#else
#define	ERRORCHECKMUTEX	PTHREAD_MUTEX_INITIALIZER
#endif

static inline int
mutex_init(mutex_t *mp, int type, void *arg __attribute__((__unused__)))
{
	pthread_mutexattr_t attr;
	int ret;

	if ((type & ~(USYNC_THREAD | LOCK_ERRORCHECK | LOCK_RECURSIVE)) != 0)
		return (EINVAL);

	if ((type & (LOCK_ERRORCHECK | LOCK_RECURSIVE)) == 0)
		return (pthread_mutex_init(mp, NULL));

	if ((ret = pthread_mutexattr_init(&attr)) != 0)
		return (ret);
	ret = pthread_mutexattr_settype(&attr,
	    (type & LOCK_RECURSIVE) != 0 ? PTHREAD_MUTEX_RECURSIVE :
	    PTHREAD_MUTEX_ERRORCHECK);
	if (ret == 0)
		ret = pthread_mutex_init(mp, &attr);
	(void) pthread_mutexattr_destroy(&attr);

	return (ret);
}

static inline int
mutex_destroy(mutex_t *mp)
{
	return (pthread_mutex_destroy(mp));
}

static inline int
mutex_lock(mutex_t *mp)
{
	return (pthread_mutex_lock(mp));
}

static inline int
mutex_trylock(mutex_t *mp)
{
	return (pthread_mutex_trylock(mp));
}

static inline int
mutex_unlock(mutex_t *mp)
{
	return (pthread_mutex_unlock(mp));
}

static inline int
cond_init(cond_t *cvp, int type __attribute__((__unused__)),
    void *arg __attribute__((__unused__)))
{
	return (pthread_cond_init(cvp, NULL));
}

static inline int
cond_destroy(cond_t *cvp)
{
	return (pthread_cond_destroy(cvp));
}

static inline int
cond_wait(cond_t *cvp, mutex_t *mp)
{
	return (pthread_cond_wait(cvp, mp));
}

static inline int
cond_signal(cond_t *cvp)
{
	return (pthread_cond_signal(cvp));
}

static inline int
cond_broadcast(cond_t *cvp)
{
	return (pthread_cond_broadcast(cvp));
}

/*
 * illumos' <synch.h> also spells lock/unlock the kernel way, aborting rather
 * than returning an error.  ctf_dwarf.c's DWARF_LOCK()/DWARF_UNLOCK() use
 * those.
 */
static inline void
mutex_enter(mutex_t *mp)
{
	if (pthread_mutex_lock(mp) != 0)
		abort();
}

static inline void
mutex_exit(mutex_t *mp)
{
	if (pthread_mutex_unlock(mp) != 0)
		abort();
}

/*
 * POSIX exposes no way to ask whether the calling thread holds a
 * pthread_mutex_t, so these can only answer "yes" -- the assertions that use
 * them become vacuous rather than wrong.
 */
#define	MUTEX_HELD(mp)		(1)
#define	RW_LOCK_HELD(rw)	(1)
#define	RW_READ_HELD(rw)	(1)
#define	RW_WRITE_HELD(rw)	(1)

#ifdef	__cplusplus
}
#endif

#endif	/* _CTF_NATIVE_SYNCH_H */
