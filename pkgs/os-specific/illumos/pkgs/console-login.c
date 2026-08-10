/*
 * A console "getty" for a system that has no ttymon(8) and no devfsadm(8).
 *
 * On a modern illumos system the interactive console is not an inittab entry at
 * all: cmd/initpkg/inittab says so in as many words ("It is no longer necessary
 * to edit inittab(5) directly; administrators should use ... SMF"), and the
 * console comes from svc:/system/console-login:default, whose start method is
 * cmd/svc/milestone/console-login -- a shell script that works out the console
 * device and runs
 *
 *     /usr/lib/saf/ttymon -g -d /dev/console -l console -m ldterm,ttcompat ...
 *
 * That is the shape this stands in for, and it is worth being precise about
 * why none of it is reachable here. Four separate pieces are missing:
 *
 *   * svc.startd runs, but svc.configd cannot open a repository (there is no
 *     /etc/svc/repository.db and no sqlite-backed store to build one in), so
 *     startd goes to maintenance mode and never starts a service. Anything
 *     that depends on SMF therefore cannot be how we get a console.
 *
 *   * ttymon(8) is not packaged, nor is login(1), nor the PAM modules login
 *     would authenticate through.
 *
 *   * ttymon(8) itself is not packaged (nor is login(1), nor the PAM modules
 *     login would authenticate through).
 *
 *   * /dev/console is not packaged either -- devfsadm(8) creates it, and
 *     devfsadm is not here. The device has to be hunted for by its /devices
 *     path, exactly as init-shell.c does; see that file for the reasoning
 *     behind the candidate list and behind opening it O_RDWR.
 *
 *   * The `-m ldterm,ttcompat` is autopush's job on a booted system, via the
 *     `asy -1 0 ldterm ttcompat` line of /etc/iu.ap and the
 *     `ap::sysinit:/sbin/autopush -f /etc/iu.ap` inittab entry. Neither
 *     autopush(8) nor sad(4D)'s configuration is packaged, so a freshly opened
 *     asy(4D) here is a bare STREAMS device: no line discipline, therefore no
 *     canonical mode and no echo, and no ioctl that could turn either on.
 *
 * So this program stands in for all of it: it puts a root shell on the console
 * with a working line discipline, and respawns it when it exits. There is no
 * authentication, which is deliberate and is the same posture as
 * `illumos.init-shell` -- login(1) needs PAM modules that are not packaged.
 *
 * It is meant to be replaced, in two steps rather than one. Packaging
 * autopush(8) and /etc/iu.ap, with the `ap::sysinit:` line the gate's inittab
 * already has, would let the I_PUSH below go. Getting svc.configd a working
 * repository would let SMF start system/console-login, at which point this and
 * its inittab entry can both be deleted -- which is the point of keeping the
 * entry a plain `sysinit` line rather than growing it into something SMF would
 * have to be taught about.
 *
 * How it is started, and why it daemonises
 * ----------------------------------------
 * init(8) runs *every* inittab command as `/sbin/sh -c <command>` (the execle()
 * calls in cmd/init/init.c), and the child has FD_CLOEXEC set on every
 * descriptor first, so the command starts with no open file descriptors at all
 * -- which is why this program has to open the console itself rather than
 * inherit it, and why the usual `</dev/console >/dev/msglog` redirections on
 * an inittab line are not merely unavailable here but unnecessary.
 *
 * The entry is `sysinit` rather than `respawn` -- the action the pre-SMF
 * `co:234:respawn:...ttymon` line used -- and this program forks and lets its
 * parent exit. Neither is a stylistic choice:
 *
 *   * A `respawn` entry is only spawned when the run level named in its rstate
 *     field is the current one, and init boots with `cur_state = 0` -- see the
 *     comment at cmd/init/init.c:735, "It's fine to boot up with state as
 *     zero, because startd will later tell us the real state".
 *     state_to_mask(0) is 0, so *no* respawn entry matches until svc.startd
 *     comes up far enough to report a run level. A console that only appears
 *     if SMF works is precisely the wrong way round: the console is what one
 *     needs in order to find out why SMF did not.
 *
 *   * `sysinit` entries are run unconditionally at boot, before svc.startd is
 *     started, and init *waits* for each one. So this program must return
 *     promptly: the parent exits as soon as the supervisor is forked off, and
 *     the supervisor is reparented to init and carries on. init does not know
 *     about it, which also means init will not kill it on a run-level change.
 *
 * The respawn loop is therefore ours rather than init's. The supervisor never
 * takes a controlling terminal; each shell it forks does its own setsid() and
 * TIOCSCTTY, as in init-shell.c, so that the terminal belongs to the shell's
 * session.
 *
 * Freestanding -- raw `syscall` traps, -nostdlib -- for the same reason the
 * inits are: this is part of getting to a prompt, so it must not depend on the
 * userland it exists to let you inspect. Syscall numbers come from
 * uts/intel/os/name_to_sysnum.
 */

typedef unsigned int tcflag_t;
typedef unsigned char cc_t;

#define	NCCS	19

struct termios {
	tcflag_t c_iflag;
	tcflag_t c_oflag;
	tcflag_t c_cflag;
	tcflag_t c_lflag;
	cc_t c_cc[NCCS];
};

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

/*
 * The generic form: reports the carry flag, which is how illumos signals an
 * error return, and the second return value in %rdx, which is how forksys(2)
 * tells the child from the parent (lwp_setrval(), uts/intel/os/sundep.c).
 */
static long
sysx(long num, long a, long b, long c, long d, long *failed, long *rval2)
{
	long ret, r2;
	unsigned char carry;
	register long r10 __asm__("r10") = d;

	__asm__ volatile ("syscall; setc %2"
	    : "=a" (ret), "=d" (r2), "=q" (carry)
	    : "a" (num), "D" (a), "S" (b), "1" (c), "r" (r10)
	    : "rcx", "r11", "memory");
	if (failed != 0)
		*failed = carry;
	if (rval2 != 0)
		*rval2 = r2;
	return (ret);
}

#define	SYS_exit	1
#define	SYS_write	4
#define	SYS_open	5
#define	SYS_close	6
#define	SYS_pgrpsys	39	/* setpgrp(2) */
#define	SYS_ioctl	54
#define	SYS_exece	59
#define	SYS_fcntl	62
#define	SYS_waitsys	107
#define	SYS_forksys	142
#define	SYS_nanosleep	199

#define	O_RDWR		2
#define	O_NDELAY	4
#define	O_NOCTTY	0x800
#define	F_DUP2FD	9
#define	PGRPSYS_SETSID	3
#define	TIOCSCTTY	(('t' << 8) | 132)

#define	P_ALL		7
#define	WEXITED		0001
#define	EINTR		4

#define	_TIOC		('T' << 8)
#define	TCGETS		(_TIOC | 13)
#define	TCSETSF		(_TIOC | 16)

/* uts/common/sys/stropts.h:227,230,239 */
#define	STR		('S' << 8)
#define	I_PUSH		(STR | 002)
#define	I_FIND		(STR | 013)

/* uts/common/sys/termios.h */
#define	BRKINT	0000002
#define	ICRNL	0000400
#define	IXON	0002000
#define	IMAXBEL	0020000
#define	OPOST	0000001
#define	ONLCR	0000004
#define	B9600	13
#define	CS8	0000060
#define	CREAD	0000200
#define	CLOCAL	0004000
#define	ISIG	0000001
#define	ICANON	0000002
#define	ECHO	0000010
#define	ECHOE	0000020
#define	ECHOK	0000040
#define	ECHOCTL	0001000
#define	ECHOKE	0004000
#define	IEXTEN	0100000

#define	VINTR	0
#define	VQUIT	1
#define	VERASE	2
#define	VKILL	3
#define	VEOF	4
#define	VSTART	8
#define	VSTOP	9
#define	VSUSP	10
#define	VREPRINT 12
#define	VDISCARD 13
#define	VWERASE	14
#define	VLNEXT	15
#define	VERASE2	17

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

/* The supervisor's own console, opened O_NOCTTY: it must not own a terminal. */
static long cfd = -1;

static void
say(const char *s, long n)
{
	(void) sys(SYS_write, cfd, (long)s, n);
}

static long
open_console(long extra_flags)
{
	long i, failed, fd;

	for (i = 0; consoles[i] != 0; i++) {
		fd = sysx(SYS_open, (long)consoles[i],
		    O_RDWR | O_NDELAY | extra_flags, 0, 0, &failed, 0);
		if (!failed)
			return (fd);
	}
	return (-1);
}

static void
sleep_secs(long secs)
{
	long ts[2];

	ts[0] = secs;
	ts[1] = 0;
	(void) sys(SYS_nanosleep, (long)ts, 0, 0);
}

/*
 * Put a line discipline on the console stream, which is what autopush(8) would
 * have done from /etc/iu.ap on a system that had either.
 *
 * I_FIND first, so this stays correct if the stream ever *does* arrive
 * pre-configured: pushing a second ldterm would put two line disciplines in
 * series, and every typed character would echo twice. This matters more here
 * than it did in init-shell, because the loop below opens the same device again
 * for every shell it starts.
 */
static void
push_ldterm(long fd)
{
	static const char ldterm[] = "ldterm";
	static const char ttcompat[] = "ttcompat";
	long failed, found;

	found = sysx(SYS_ioctl, fd, I_FIND, (long)ldterm, 0, &failed, 0);
	if (!failed && found == 1)
		return;

	(void) sys(SYS_ioctl, fd, I_PUSH, (long)ldterm);
	(void) sys(SYS_ioctl, fd, I_PUSH, (long)ttcompat);
}

/*
 * Give the console the termios a line-oriented terminal is expected to have.
 * Read-modify-write rather than assign, so whatever ldterm and the driver
 * already agree on about baud and character size is left alone. ECHO in
 * particular is clear in ldterm's defaults; on a real system setting it is
 * ttymon's job.
 */
static void
setup_tty(long fd)
{
	struct termios t;
	long failed;
	int i;

	(void) sysx(SYS_ioctl, fd, TCGETS, (long)&t, 0, &failed, 0);
	if (failed) {
		/*
		 * No line discipline at all: build the settings from scratch.
		 * All four flag words, not just c_cflag -- the |= below is a
		 * read-modify-write, and reading an uninitialised automatic
		 * would fold stack garbage into the terminal settings.
		 */
		for (i = 0; i < NCCS; i++)
			t.c_cc[i] = 0;
		t.c_iflag = 0;
		t.c_oflag = 0;
		t.c_lflag = 0;
		t.c_cflag = B9600 | CS8 | CREAD | CLOCAL;
	}

	t.c_iflag |= BRKINT | ICRNL | IXON | IMAXBEL;
	t.c_oflag |= OPOST | ONLCR;
	t.c_cflag |= CREAD | CLOCAL;
	t.c_lflag |= ISIG | ICANON | ECHO | ECHOE | ECHOK | ECHOCTL | ECHOKE |
	    IEXTEN;

	t.c_cc[VINTR] = 3;	/* ^C */
	t.c_cc[VQUIT] = 28;	/* ^\ */
	t.c_cc[VERASE] = 8;	/* ^H -- and VERASE2 below takes DEL */
	t.c_cc[VERASE2] = 127;
	t.c_cc[VKILL] = 21;	/* ^U */
	t.c_cc[VEOF] = 4;	/* ^D */
	t.c_cc[VSTART] = 17;	/* ^Q */
	t.c_cc[VSTOP] = 19;	/* ^S */
	t.c_cc[VSUSP] = 26;	/* ^Z */
	t.c_cc[VREPRINT] = 18;	/* ^R */
	t.c_cc[VDISCARD] = 15;	/* ^O */
	t.c_cc[VWERASE] = 23;	/* ^W */
	t.c_cc[VLNEXT] = 22;	/* ^V */

	(void) sys(SYS_ioctl, fd, TCSETSF, (long)&t);
}

/* Runs in the shell's process, and either execs or exits. */
static void
run_shell(void)
{
	long failed, fd;

	/*
	 * Become a session leader first: TIOCSCTTY only works for one, and the
	 * terminal has to be acquired after the session exists. Doing it here
	 * rather than in the supervisor is what keeps the console owned by the
	 * shell's session, so that the next shell can take it when this one
	 * dies.
	 */
	(void) sys(SYS_pgrpsys, PGRPSYS_SETSID, 0, 0);

	fd = open_console(0);
	if (fd < 0)
		(void) sys(SYS_exit, 1, 0, 0);

	(void) sys(SYS_ioctl, fd, TIOCSCTTY, 0);
	push_ldterm(fd);
	setup_tty(fd);

	(void) sys(SYS_fcntl, fd, F_DUP2FD, 0);
	(void) sys(SYS_fcntl, fd, F_DUP2FD, 1);
	(void) sys(SYS_fcntl, fd, F_DUP2FD, 2);
	if (fd > 2)
		(void) sys(SYS_close, fd, 0, 0);

	(void) sysx(SYS_exece, (long)prog, (long)prog_argv, (long)prog_envp,
	    0, &failed, 0);

	cfd = 2;
	say("console-login: exec of the shell failed\n", 40);
	(void) sys(SYS_exit, 1, 0, 0);
}

/*
 * How many times to bring the shell back before giving up on it. Respawning is
 * what makes an interactive `exit` recoverable; the cap is what keeps a shell
 * that dies instantly -- a piped script's input having run out, say -- from
 * scrolling the console forever.
 */
#define	MAX_RESPAWNS	10

/*
 * The kernel enters a fresh process with %rsp pointing at argc, which is not
 * the alignment the SysV ABI promises a *called* function -- that is
 * established by crt1.o, which -nostdlib means we do not have. gcc assumes it
 * and emits `movaps` to stack slots, and `movaps` to an unaligned address is a
 * #GP delivered as SIGSEGV. So align in asm, then enter C.
 */
__asm__(
	".globl _start\n"
	"_start:\n"
	"	andq $-16, %rsp\n"
	"	call console_main\n"
	"	hlt\n");

static void
supervise(void)
{
	long failed, rval2, pid, err, respawns = 0;
	/* siginfo_t, which we only need as a landing pad, is 256 bytes. */
	long si[64];

	cfd = open_console(O_NOCTTY);

	for (;;) {
		pid = sysx(SYS_forksys, 0, 0, 0, 0, &failed, &rval2);
		if (failed) {
			say("console-login: fork failed\n", 27);
			(void) sys(SYS_exit, 1, 0, 0);
		}
		if (rval2 == 1) {
			/* Child: `pid` holds the parent's pid, not ours. */
			run_shell();
			(void) sys(SYS_exit, 1, 0, 0);
		}

		/*
		 * Wait for *that* child specifically. This process is not pid 1
		 * so it does not collect the system's orphans, but it does
		 * collect its own shell's -- a backgrounded job, say -- and
		 * treating any successful wait as the shell exiting would start
		 * a second shell on top of a live one. si_pid is the first
		 * member of siginfo_t's union, which on LP64 begins at byte 16:
		 * three ints and the explicit `si_pad`
		 * (uts/common/sys/siginfo.h).
		 */
		for (;;) {
			err = sysx(SYS_waitsys, P_ALL, 0, (long)si, WEXITED,
			    &failed, 0);
			if (failed) {
				/* EINTR is worth retrying; ECHILD is not. */
				if (err == EINTR)
					continue;
				break;
			}
			if ((long)((int *)si)[4] == pid)
				break;
		}

		if (++respawns > MAX_RESPAWNS) {
			say("console-login: shell keeps exiting; giving up\n",
			    45);
			break;
		}
		say("\nconsole-login: restarting the console shell\n", 44);
		sleep_secs(1);
	}

	(void) sys(SYS_exit, 0, 0, 0);
}

int
console_main(void)
{
	long failed, rval2;

	/*
	 * Fork and let the parent go. init runs this from a `sysinit` entry and
	 * waits for it -- see the header comment -- so returning promptly is
	 * what lets the rest of the boot, svc.startd included, proceed.
	 */
	(void) sysx(SYS_forksys, 0, 0, 0, 0, &failed, &rval2);
	if (failed || rval2 != 1)
		(void) sys(SYS_exit, 0, 0, 0);

	supervise();

	/*NOTREACHED*/
	(void) sys(SYS_exit, 0, 0, 0);
	return (0);
}
