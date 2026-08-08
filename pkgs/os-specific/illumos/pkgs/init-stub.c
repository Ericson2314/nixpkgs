/*
 * A stand-in for /sbin/init: no libc, no PAM, no SMF.  It exists only to prove
 * that the kernel got far enough to exec a user process from the root
 * filesystem.  illumos' real init needs -lpam -lbsm -lcontract -lscf, none of
 * which is ported yet.
 *
 * This does get exec'd and does execute.  The console writes below are *not*
 * how that is checked, though: /dev/console does not exist yet (devfsadm(8)
 * creates it, and there is no userland to run it), and writes to the wscons
 * and iwscn device nodes report success but do not reach the port.  See the
 * log in boot-qemu.sh.  The uadmin(A_SHUTDOWN, AD_POWEROFF) at the end is the
 * check: the machine powers itself off and qemu exits.
 *
 * Freestanding on purpose: raw `syscall` traps, so nothing here depends on
 * libc, crt1.o or ld.so.1.  Syscall numbers are from
 * uts/intel/os/name_to_sysnum, and the uadmin(2) constants from
 * uts/common/sys/uadmin.h.
 */

static long
sys(long num, long a, long b, long c)
{
	long ret;
	__asm__ volatile ("syscall"
	    : "=a" (ret)
	    : "a" (num), "D" (a), "S" (b), "d" (c)
	    : "rcx", "r11", "memory");
	return (ret);
}

#define	SYS_exit	1
#define	SYS_write	4
#define	SYS_open	5
#define	SYS_pause	29
#define	SYS_uadmin	55

#define	A_SHUTDOWN	2
#define	AD_POWEROFF	6
#define	A_REBOOT	1
#define	AD_BOOT		1

static const char msg[] =
    "\n*** hello from userland: cross-built illumos reached /sbin/init ***\n";

void
_start(void)
{
	int fd;

	/* Whatever the kernel handed us, if anything. */
	(void) sys(SYS_write, 1, (long)msg, sizeof (msg) - 1);
	(void) sys(SYS_write, 2, (long)msg, sizeof (msg) - 1);

	/* O_WRONLY == 1 */
	fd = (int)sys(SYS_open, (long)"/dev/console", 1, 0);
	if (fd >= 0)
		(void) sys(SYS_write, fd, (long)msg, sizeof (msg) - 1);

	fd = (int)sys(SYS_open, (long)"/dev/msglog", 1, 0);
	if (fd >= 0)
		(void) sys(SYS_write, fd, (long)msg, sizeof (msg) - 1);

	/*
	 * A console message is the nice proof that we ran, but not a reliable
	 * one: consconfig() re-plumbs the console after the root mount, and if
	 * that plumbing does not reach the emulated 16550 the writes above just
	 * vanish. So make an out-of-band signal too. uadmin(A_SHUTDOWN,
	 * AD_POWEROFF) turns the machine off, which qemu reports by exiting: a
	 * boot that ends in qemu exiting promptly rather than hitting the
	 * harness timeout is proof that user code ran, whatever the console did.
	 */
	(void) sys(SYS_uadmin, A_SHUTDOWN, AD_POWEROFF, 0);
	(void) sys(SYS_uadmin, A_REBOOT, AD_BOOT, 0);

	/*
	 * If that returns, do not exit -- exit.c:restart_init() would respawn
	 * us forever. Park in pause(2) instead.
	 */
	for (;;)
		(void) sys(SYS_pause, 0, 0, 0);
}
