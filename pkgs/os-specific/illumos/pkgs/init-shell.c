/*
 * An /sbin/init that hands the console to an interactive shell.
 *
 * Freestanding on purpose -- raw `syscall` traps, `-nostdlib` -- so that
 * nothing here depends on the illumos userland working. That matters: this is
 * the program that has to run *before* we know whether anything else does.
 * Syscall numbers come from uts/intel/os/name_to_sysnum.
 *
 * The shell to run is baked in at build time as PROG (see init-shell.nix).
 *
 * Three things here are less obvious than they look, and all three were bugs
 * before they were code:
 *
 *   * /dev/console does not exist. devfsadm(8) creates it and there is no
 *     userland to run devfsadm, so we walk a list of candidates and take the
 *     first that opens. On qemu's default i440fx the one that reaches the
 *     serial port is the ISA bridge under the PCI nexus. This is
 *     chipset-specific, which is exactly the problem devfsadm exists to solve.
 *
 *   * The console must be opened O_RDWR. Opening it write-only and duping that
 *     onto fd 0 gets you a shell that prints its prompt and immediately reads
 *     EOF -- it logs out before you can type anything, which looks like a
 *     broken tty and is not.
 *
 *   * setsid() before opening it, then TIOCSCTTY. Without a controlling
 *     terminal bash starts with "cannot set terminal process group (-1):
 *     Inappropriate ioctl for device" and "no job control in this shell".
 *     illumos has no setsid syscall of its own: it is setpgrp(2) with
 *     PGRPSYS_SETSID (uts/common/sys/pgrpsys.h:32).
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

/* exece(2) takes four arguments; the fourth is a flags word and must be 0. */
static long
sys4(long num, long a, long b, long c, long d, long *failed)
{
	long ret;
	unsigned char carry;
	register long r10 __asm__("r10") = d;

	__asm__ volatile ("syscall; setc %1"
	    : "=a" (ret), "=q" (carry)
	    : "a" (num), "D" (a), "S" (b), "d" (c), "r" (r10)
	    : "rcx", "r11", "memory");
	*failed = carry;
	return (ret);
}

static long
sys_open(const char *path, long flags, long *failed)
{
	long ret;
	unsigned char carry;

	__asm__ volatile ("syscall; setc %1"
	    : "=a" (ret), "=q" (carry)
	    : "a" (5L), "D" ((long)path), "S" (flags), "d" (0L)
	    : "rcx", "r11", "memory");
	*failed = carry;
	return (ret);
}

#define	SYS_write	4
#define	SYS_pgrpsys	39	/* setpgrp(2) */
#define	SYS_ioctl	54
#define	SYS_exece	59
#define	SYS_fcntl	62
#define	SYS_uadmin	55

#define	O_RDWR		2
#define	O_NDELAY	4
#define	F_DUP2FD	9
#define	PGRPSYS_SETSID	3
#define	TIOCSCTTY	(('t' << 8) | 132)

#define	A_SHUTDOWN	2
#define	AD_POWEROFF	6

static const char *const consoles[] = {
	"/dev/console",
	"/dev/msglog",
	"/devices/pci@0,0/isa@1/asy@1,3f8:a",
	"/devices/isa/asy@1,3f8:a",
	0
};

static const char *const prog_argv[] = {
	"-bash", "--norc", "--noprofile", "-i", 0
};

static const char *const prog_envp[] = {
	"PATH=/bin:/usr/bin:/sbin",
	"HOME=/",
	"TERM=vt100",
	"PS1=illumos\\$ ",
	0
};

static const char prog[] = PROG;

static long cfd = -1;

static void
say(const char *s, long n)
{
	(void) sys(SYS_write, cfd, (long)s, n);
}

/*
 * A note on the "exited on fatal signal 1" you will see once, every time the
 * shell exits:
 *
 *     logout
 *     WARNING: init(8) exited with status 0: restarting automatically
 *     WARNING: init(8) exited on fatal signal 1: restarting automatically
 *     init: starting shell on the console
 *     illumos#
 *
 * It is understood, deterministic and benign, but it is not fixable from here.
 * When init exits, restart_init() (uts/common/os/exit.c) calls
 * freectty(B_TRUE) at :288 -- which does pgsignal(stp->sd_pgidp, SIGHUP)
 * (uts/common/os/session.c:514), signalling its own foreground process group,
 * the one it is still a member of -- and *then* execs the replacement init at
 * :295 in the same process. The replacement therefore starts with a pending
 * SIGHUP sent by its predecessor, and SIGHUP's disposition at that moment is
 * SIG_DFL, so it dies before its first instruction. exec preserves SIG_IGN but
 * we never get the chance to set it; calling sigaction() here is too late. The
 * second restart succeeds because by then there is no controlling terminal
 * left to free, which is why you get a shell back.
 *
 * The real fix is for init to fork and let the *child* take the controlling
 * terminal and exec the shell, so that pid 1 never owns a tty and
 * restart_init() has nothing to hang up. That is what a real init does, and it
 * is the right next step here; it needs fork/waitid in freestanding code,
 * which this does not yet have.
 */

int
_start(void)
{
	long i, failed, fd;

	/*
	 * Become a session leader first: TIOCSCTTY below only works for one,
	 * and the terminal has to be acquired after the session exists.
	 */
	(void) sys(SYS_pgrpsys, PGRPSYS_SETSID, 0, 0);

	for (i = 0; consoles[i] != 0; i++) {
		fd = sys_open(consoles[i], O_RDWR | O_NDELAY, &failed);
		if (!failed) {
			cfd = fd;
			break;
		}
	}
	if (cfd < 0) {
		/* Nothing to talk to; do not spin forever. */
		(void) sys(SYS_uadmin, A_SHUTDOWN, AD_POWEROFF, 0);
		for (;;)
			;
	}

	(void) sys(SYS_ioctl, cfd, TIOCSCTTY, 0);

	(void) sys(SYS_fcntl, cfd, F_DUP2FD, 0);
	(void) sys(SYS_fcntl, cfd, F_DUP2FD, 1);
	(void) sys(SYS_fcntl, cfd, F_DUP2FD, 2);

	say("\ninit: starting shell on the console\n", 36);

	(void) sys4(SYS_exece, (long)prog, (long)prog_argv, (long)prog_envp,
	    0, &failed);

	/*
	 * Only reached if the exec failed. Say so on the console -- it is the
	 * one diagnostic anybody debugging this will want -- and power off
	 * rather than let restart_init() spin.
	 */
	say("init: exec failed\n", 18);
	(void) sys(SYS_uadmin, A_SHUTDOWN, AD_POWEROFF, 0);
	for (;;)
		;
}
