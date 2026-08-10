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
 * Structure: pid 1 forks, and the *child* takes the controlling terminal and
 * execs the shell. pid 1 itself never opens a controlling terminal and never
 * returns from `_start`; it sits in waitsys(2) and respawns the shell when it
 * dies. Both halves of that matter, for two independent reasons:
 *
 *   * If init exits, the kernel restarts it, forever. A shell reading a piped
 *     script exits the moment the script's input runs out, so an init that
 *     merely exec'd the shell turned every non-interactive boot into an
 *     unbounded restart loop. Waiting instead of exiting is what makes the
 *     console scriptable.
 *
 *   * restart_init() (uts/common/os/exit.c) resets every SIG_IGN disposition
 *     to SIG_DFL at :216-222, calls freectty(B_TRUE) at :288 -- which does
 *     pgsignal(stp->sd_pgidp, SIGHUP) (uts/common/os/session.c:514) against
 *     its own foreground process group -- and only *then* execs the
 *     replacement init at :295, in the same process. So a pid 1 that owns a
 *     controlling terminal hangs up its own successor before that successor's
 *     first instruction, and no sigaction() in the successor can prevent it.
 *     Keeping the tty in the child means freectty() has nothing to signal.
 *
 * Four other things here are less obvious than they look, and all four were
 * bugs before they were code:
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
 *
 *   * A freshly opened asy(4D) is a *bare* STREAMS device. Nothing but the
 *     driver is on the stream, so there is no line discipline: no canonical
 *     mode, no ECHO, and no ioctl that could turn either on -- TCSETS is
 *     answered by asy(4D) itself, which rejects what it does not implement.
 *     The symptom is a shell whose prompt appears and whose input works, but
 *     which never shows a character you type; `stty echo icanon` on it says
 *     "unable to perform all requested operations".
 *
 *     Pushing the line discipline is not consconfig()'s job and never was.
 *     For a serial console -- CONSOLE_TIP, which is what `console=ttya`
 *     selects -- consconfig_init_input() only calls i_consconfig_createvp()
 *     on the device path and pushes nothing at all
 *     (uts/common/io/consconfig_dacf.c). ldterm and ttcompat reach the stream
 *     through *autopush*: the `asy -1 0 ldterm ttcompat` line of /etc/iu.ap
 *     (cmd/netadm/iu.ap.sh), loaded into sad(4D) by the
 *     `ap::sysinit:/sbin/autopush -f /etc/iu.ap` entry in inittab. Neither
 *     autopush(8) nor an inittab exists here, so init pushes the two modules
 *     itself, in that order, and only then does TCSETS mean anything.
 *
 *   * Even with ldterm on the stream, ECHO is clear in its defaults, so typed
 *     characters are still invisible. Nothing else sets this up -- on a real
 *     system it is what ttymon(8) is for -- so init does a TCSETS with a
 *     conventional line-oriented setting before exec'ing the shell.
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
 * tells the child from the parent (lwp_setrval() in uts/intel/os/sundep.c).
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

#define	SYS_write	4
#define	SYS_open	5
#define	SYS_mount	21
#define	SYS_pgrpsys	39	/* setpgrp(2) */
#define	SYS_ioctl	54
#define	SYS_uadmin	55
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

#define	MS_DATA		0x0004

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

/* pid 1's own console, opened O_NOCTTY: see the header comment. */
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
poweroff(void)
{
	(void) sys(SYS_uadmin, A_SHUTDOWN, AD_POWEROFF, 0);
	for (;;)
		;
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
 * Put a line discipline on the console stream, which is what autopush(8)
 * would have done from /etc/iu.ap on a system that had either. See the header
 * comment: without this the console is a bare asy(4D) and no amount of TCSETS
 * will give it echo.
 *
 * I_FIND first, so that this stays correct if the stream ever *does* arrive
 * pre-configured -- pushing a second ldterm would put two line disciplines in
 * series, which echoes every character twice. Errors are ignored beyond that:
 * if the modules cannot be loaded there is nothing useful to do about it, and
 * setup_tty() below already copes with a stream that answers no TCGETS.
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
 * Read-modify-write rather than assign, so that whatever ldterm and the driver
 * already agree on about baud and character size is left alone; the flags we
 * care about are the ones nothing else sets.
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
		 * No line discipline at all: build one from scratch. All four
		 * flag words, not just c_cflag -- the |= below is a
		 * read-modify-write, and reading an uninitialised automatic
		 * would fold whatever was on the stack into the terminal
		 * settings.
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

/*
 * mount(2) takes six arguments here, so it needs %r8 and %r9 as well.
 *
 * The kernel-side signature -- mount(long *lp, rval_t *rp), taking a pointer
 * to its arguments -- is a red herring: `mount` is a SYSENT_AP entry
 * (uts/common/os/sysent.c:463), and syscall_ap() is what turns the *ordinary*
 * register-and-stack arguments the trap collected into the array that mount()
 * then walks. Passing a pointer to a ready-made array in argument one, as an
 * earlier version of this did, just means mount() reads `spec` as a pointer
 * and everything after it as garbage. It fails silently, which is why /tmp
 * stayed read-only.
 *
 * The declared argument count is eight, so the trap will also fetch arguments
 * seven and eight from the user stack. They are `optptr`/`optlen`, which
 * mount() only looks at under MS_OPTIONSTR (uts/common/fs/vfs.c:1417); we do
 * not set it, so whatever it collects there is never dereferenced.
 */
static long
sys6(long num, long a, long b, long c, long d, long e, long f, long *failed)
{
	long ret;
	unsigned char carry;
	register long r10 __asm__("r10") = d;
	register long r8 __asm__("r8") = e;
	register long r9 __asm__("r9") = f;

	__asm__ volatile ("syscall; setc %1"
	    : "=a" (ret), "=q" (carry)
	    : "a" (num), "D" (a), "S" (b), "d" (c), "r" (r10), "r" (r8),
	      "r" (r9)
	    : "rcx", "r11", "memory");
	*failed = carry;
	return (ret);
}

/*
 * Best effort: if there is no tmpfs module, or /tmp is missing, the shell
 * simply gets a read-only /tmp, which is what it had before.
 */
static void
mount_tmp(void)
{
	static const char spec[] = "swap";
	static const char dir[] = "/tmp";
	static const char fstype[] = "tmpfs";
	char msg[] = "init: /tmp mount failed, errno NN\n";
	long ret, failed;

	/*
	 * MS_DATA is not optional even with no data: without it (or MS_FSS)
	 * mount() reads `fstype` as an *index* into vfssw[] rather than as a
	 * name (uts/common/fs/vfs.c:1175-1200).
	 */
	ret = sys6(SYS_mount, (long)spec, (long)dir, MS_DATA, (long)fstype,
	    0, 0, &failed);

	if (failed) {
		/* Two digits covers every errno this can plausibly return. */
		msg[30] = (char)('0' + ((ret / 10) % 10));
		msg[31] = (char)('0' + (ret % 10));
		say(msg, sizeof (msg) - 1);
	}
}

/* Runs in the child, and either execs or dies. */
static void
run_shell(void)
{
	long failed, fd;

	/*
	 * Become a session leader first: TIOCSCTTY below only works for one,
	 * and the terminal has to be acquired after the session exists. This
	 * is the child, so pid 1 stays session- and terminal-less.
	 */
	(void) sys(SYS_pgrpsys, PGRPSYS_SETSID, 0, 0);

	fd = open_console(0);
	if (fd < 0)
		poweroff();

	(void) sys(SYS_ioctl, fd, TIOCSCTTY, 0);
	push_ldterm(fd);
	setup_tty(fd);

	(void) sys(SYS_fcntl, fd, F_DUP2FD, 0);
	(void) sys(SYS_fcntl, fd, F_DUP2FD, 1);
	(void) sys(SYS_fcntl, fd, F_DUP2FD, 2);

	(void) sysx(SYS_exece, (long)prog, (long)prog_argv, (long)prog_envp,
	    0, &failed, 0);

	/*
	 * Only reached if the exec failed. Say so on the console -- it is the
	 * one diagnostic anybody debugging this will want.
	 */
	cfd = fd;
	say("init: exec failed\n", 18);
	poweroff();
}

/*
 * How many times to bring the shell back before giving up on it. Respawning
 * is what makes an interactive `exit` recoverable; the cap is what keeps a
 * shell that dies instantly -- a script's input having run out, say -- from
 * scrolling the console forever. On the cap, pid 1 parks rather than exits,
 * because exiting is what the kernel turns into a restart loop.
 */
#define	MAX_RESPAWNS	5

/*
 * The kernel enters a fresh process with %rsp pointing at argc, which is not
 * the alignment the SysV ABI promises a *called* function -- that is
 * established by crt1.o, which -nostdlib means we do not have. gcc is entitled
 * to assume it and does: it emits `movaps` to stack slots as soon as there is
 * enough on the stack to be worth vectorising, and `movaps` to an unaligned
 * address is a #GP that arrives as SIGSEGV before any of our code could report
 * it -- which the kernel then turns into an init restart loop. So align the
 * stack in asm, and only then enter C.
 */
__asm__(
	".globl _start\n"
	"_start:\n"
	"	andq $-16, %rsp\n"
	"	call init_main\n"
	"	hlt\n");

int
init_main(void)
{
	long failed, rval2, pid, err, respawns = 0;
	/* siginfo_t, which we only need as a landing pad, is 256 bytes. */
	long si[64];

	cfd = open_console(O_NOCTTY);

	mount_tmp();

	for (;;) {
		say("\ninit: starting shell on the console\n", 36);

		pid = sysx(SYS_forksys, 0, 0, 0, 0, &failed, &rval2);
		if (failed) {
			say("init: fork failed\n", 18);
			poweroff();
		}
		if (rval2 == 1) {
			/* Child: pid holds the *parent's* pid, not ours. */
			run_shell();
			poweroff();
		}

		/*
		 * Wait for *that* child, not for any child.
		 *
		 * pid 1 inherits every orphan on the system, so the shell is
		 * emphatically not the only child it has -- an earlier version
		 * assumed it was, and treated any successful wait as the shell
		 * exiting. Daemonising is precisely the case that breaks that:
		 * `svccfg` with SVCCFG_REPOSITORY set forks a private
		 * `svc.configd`, which double-forks (`daemonize_start()`,
		 * cmd/svc/configd/configd.c:457) so that its working process is
		 * orphaned and reparented here. When that process later exited,
		 * pid 1 reaped it, concluded the shell had died and started a
		 * second one on top of the first -- which then could not take
		 * the terminal, because the first shell still held it:
		 *
		 *     init: shell exited; restarting it
		 *     -bash: cannot set terminal process group (-1)
		 *     -bash: no job control in this shell
		 *
		 * The shell had not exited at all. So reap whatever arrives,
		 * and keep waiting unless it is the one we started. si_pid is
		 * the first member of siginfo_t's union, which on LP64 begins
		 * at byte 16 -- three ints and the explicit `si_pad`
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
			/* Somebody else's orphan. Reaped; carry on waiting. */
		}

		if (++respawns > MAX_RESPAWNS) {
			say("init: shell keeps exiting; not restarting it\n",
			    45);
			break;
		}
		say("init: shell exited; restarting it\n", 34);
		sleep_secs(1);
	}

	/*
	 * Never return: restart_init() would exec a fresh init into this same
	 * process and we would be back where we started.
	 */
	for (;;) {
		(void) sysx(SYS_waitsys, P_ALL, 0, (long)si, WEXITED,
		    &failed, 0);
		if (failed)
			sleep_secs(3600);
	}
}
