/*
 * A freestanding shim that gives the program it execs a working console.
 *
 * Real init(8) writes its diagnostics to /dev/console and /dev/msglog. Neither
 * node exists here -- devfsadm(8) creates them and it is not packaged -- so
 * when init fails early it fails silently, and all the kernel will say is
 *
 *     WARNING: init(8) exited on fatal signal 9: restarting automatically
 *
 * a couple of hundred times a second. This shim is installed as /sbin/init in
 * place of the real one, opens the console the same way init-shell.c does,
 * puts it on fds 0, 1 and 2, and then execs the real init in the *same*
 * process -- so it is still pid 1, and still behaves as init rather than as
 * telinit. Whatever init prints now has somewhere to go.
 *
 * This is a debugging tool, not a component. It is worth keeping only until
 * either devfsadm exists or the console device is created some other way.
 *
 * Everything here is deliberately the same shape as init-shell.c; see that
 * file for why the console has to be hunted for by device path, why it must be
 * opened O_RDWR, and why `_start` has to align the stack before entering C.
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

static long
sysx(long num, long a, long b, long c, long d, long *failed)
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

#define	SYS_write	4
#define	SYS_open	5
#define	SYS_ioctl	54
#define	SYS_uadmin	55
#define	SYS_exece	59
#define	SYS_fcntl	62

#define	O_RDWR		2
#define	O_NDELAY	4
#define	F_DUP2FD	9

#define	A_SHUTDOWN	2
#define	AD_POWEROFF	6

static const char *const consoles[] = {
	"/dev/console",
	"/dev/msglog",
	"/devices/pci@0,0/isa@1/asy@1,3f8:a",
	"/devices/isa/asy@1,3f8:a",
	0
};

/*
 * argv[0] is spelled as the path the kernel would have used, because init
 * looks at it: a name of "init" with pid 1 is init, anything else is telinit.
 */
static const char *const prog_argv[] = { "/sbin/init", 0 };
static const char *const prog_envp[] = { 0 };

static const char prog[] = PROG;

static long cfd = -1;

static void
say(const char *s, long n)
{
	(void) sys(SYS_write, cfd, (long)s, n);
}

__asm__(
	".globl _start\n"
	"_start:\n"
	"	andq $-16, %rsp\n"
	"	call wrap_main\n"
	"	hlt\n");

int
wrap_main(void)
{
	long i, failed, fd, err;

	for (i = 0; consoles[i] != 0; i++) {
		fd = sysx(SYS_open, (long)consoles[i], O_RDWR | O_NDELAY, 0,
		    0, &failed);
		if (!failed) {
			cfd = fd;
			break;
		}
	}

	if (cfd >= 0) {
		(void) sys(SYS_fcntl, cfd, F_DUP2FD, 0);
		(void) sys(SYS_fcntl, cfd, F_DUP2FD, 1);
		(void) sys(SYS_fcntl, cfd, F_DUP2FD, 2);
		say("init-console: exec'ing real init\n", 33);
	}

	/*
	 * No setsid() and no TIOCSCTTY, unlike init-shell: init wants to make
	 * its own decisions about sessions and the controlling terminal, and
	 * pid 1 acquiring one is what made restart_init() hang up its own
	 * successor last time.
	 */
	err = sysx(SYS_exece, (long)prog, (long)prog_argv, (long)prog_envp,
	    0, &failed);

	/*
	 * Only reached if the exec failed, in which case `err` is the errno.
	 * Two digits covers everything this can plausibly return.
	 */
	{
		char msg[] = "init-console: exec of real init failed, errno NN\n";

		msg[46] = (char)('0' + ((err / 10) % 10));
		msg[47] = (char)('0' + (err % 10));
		say(msg, sizeof (msg) - 1);
	}
	(void) sys(SYS_uadmin, A_SHUTDOWN, AD_POWEROFF, 0);
	for (;;)
		;
}
