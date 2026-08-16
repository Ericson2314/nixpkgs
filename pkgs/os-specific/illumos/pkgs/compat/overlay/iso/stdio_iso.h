/*
 * illumos spells the three standard streams as slots in a libc-owned array:
 *
 *	extern __FILE __iob[_NFILE];
 *	#define stdin (&__iob[0])
 *
 * A foreign libc owns its own FILE objects and exports them as pointers, so
 * `__iob` is simply absent at link time.  Let the gate's header declare
 * everything as usual, then repoint the three names at the host's variables.
 *
 * This is safe because nothing outside libc may look inside a FILE: it is
 * opaque by contract, so a `__FILE *` that actually addresses the host's FILE
 * is indistinguishable to every caller.  Only the spelling of the three
 * streams differs, and that is what this fixes.
 */
#include_next <iso/stdio_iso.h>

#undef stdin
#undef stdout
#undef stderr
extern __FILE *stdin, *stdout, *stderr;
