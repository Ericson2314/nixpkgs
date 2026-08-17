/*
 * A stand-in for /sbin/init: no libc, no PAM, no SMF.  It exists to prove that
 * the kernel got far enough to exec a user process from the root filesystem,
 * and to print something from user mode when it gets there.  illumos' real
 * init needs -lpam -lbsm -lcontract -lscf, none of which is ported yet.
 *
 * Freestanding on purpose: raw `syscall` traps, so nothing here depends on
 * libc, crt1.o or ld.so.1.  Syscall numbers are from
 * uts/intel/os/name_to_sysnum, and the uadmin(2) constants from
 * uts/common/sys/uadmin.h.
 *
 * Why a list of console candidates rather than just /dev/console:
 *
 *   * /dev/console does not exist.  devfsadm(8) creates it, and there is no
 *     userland to run devfsadm.  It cannot be baked into the boot image
 *     either: /dev is a mount point -- vfs_mountdev1() (common/fs/vfs.c:767)
 *     mounts the `dev` filesystem over it -- so anything underneath is
 *     shadowed, and in any case a root hsfs is read as plain iso9660 (see
 *     the boot archive builder) and plain iso9660 cannot represent a symlink.
 *
 *   * /devices/pseudo/iwscn@0:iwscn opens, and writing to it returns the full
 *     byte count, but nothing comes out.  With console=ttya the console is the
 *     CONSOLE_TIP case in consconfig_dacf.c (stdin is not a keyboard and is
 *     the same device as stdout), and there `rconsvp` is the serial device
 *     itself, not the indirect console.  iwscn redirects to the workstation
 *     console, which has no framebuffer under it here, so it swallows writes.
 *
 *   * which leaves the real device node.  That is chipset-specific -- on
 *     qemu's default i440fx the 16550 is on the ISA bridge under the PCI
 *     nexus, at /devices/pci@0,0/isa@1/asy@1,3f8:a -- hence a list, tried in
 *     order of how much we would prefer each one to be the answer.
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
sys_ok(long num, long a, long b, long c, long *failed)
{
	long ret;
	unsigned char carry;

	/* illumos reports syscall errors in the carry flag, not by sign. */
	__asm__ volatile ("syscall; setc %1"
	    : "=a" (ret), "=q" (carry)
	    : "a" (num), "D" (a), "S" (b), "d" (c)
	    : "rcx", "r11", "memory");
	*failed = carry;
	return (ret);
}

#define	SYS_exit	1
#define	SYS_write	4
#define	SYS_open	5
#define	SYS_close	6
#define	SYS_pause	29
#define	SYS_uadmin	55

#define	O_WRONLY	1
#define	O_NDELAY	4

#define	A_REBOOT	1
#define	A_SHUTDOWN	2
#define	AD_BOOT		1
#define	AD_POWEROFF	6

static const char msg[] =
    "\n*** HELLO FROM USERLAND: cross-built illumos init is running ***\n";

static const char *const consoles[] = {
	"/dev/console",
	"/dev/msglog",
	"/devices/pseudo/iwscn@0:iwscn",
	"/devices/pci@0,0/isa@1/asy@1,3f8:a",
	"/devices/isa/asy@1,3f8:a",
	0
};

void
_start(void)
{
	long i, fd, failed;

	/* Whatever the kernel handed us, if anything. */
	(void) sys(SYS_write, 1, (long)msg, sizeof (msg) - 1);
	(void) sys(SYS_write, 2, (long)msg, sizeof (msg) - 1);

	/*
	 * O_NDELAY so that opening a serial line does not block waiting for
	 * carrier detect. Write to every one that opens: at most one of them
	 * is really wired to the port, and the others discard.
	 */
	for (i = 0; consoles[i] != 0; i++) {
		fd = sys_ok(SYS_open, (long)consoles[i], O_WRONLY | O_NDELAY,
		    0, &failed);
		if (failed)
			continue;
		(void) sys(SYS_write, fd, (long)msg, sizeof (msg) - 1);
		(void) sys(SYS_close, fd, 0, 0);
	}

	/*
	 * Power the machine off. This is also the console-independent proof
	 * that we ran: qemu exits, so the run finishes in ~15s rather
	 * than sitting there until it is killed.
	 */
	(void) sys(SYS_uadmin, A_SHUTDOWN, AD_POWEROFF, 0);
	(void) sys(SYS_uadmin, A_REBOOT, AD_BOOT, 0);

	/*
	 * If both of those returned, do not exit -- exit.c:restart_init()
	 * would respawn us forever. Park in pause(2) instead.
	 */
	for (;;)
		(void) sys(SYS_pause, 0, 0, 0);
}
