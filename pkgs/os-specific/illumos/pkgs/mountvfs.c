/*
 * mountvfs -- mount(2) with an explicit filesystem type, for filesystems whose
 * mount helper we do not package.
 *
 *     mountvfs <fstype> <special> <dir> [-o options] [-r]
 *     mountvfs virtiofs store /mnt/store
 *
 * illumos' mount(8) is a dispatcher: it parses the command line, then execs
 * /usr/lib/fs/<fstype>/mount and lets that do the work. We package the NFS one
 * (it installs as /usr/lib/fs/nfs/mount) but not the generic dispatcher, and
 * virtio-fs has no helper at all -- upstream illumos has never had this
 * filesystem.
 *
 * The result is that a filesystem can be entirely working in the kernel and
 * still unmountable, because nothing in userland can issue the call. That is
 * exactly where this started: the vtfs and virtiofs modules were built and
 * staged, and the probe died on `bash: mount: command not found`.
 *
 * mount(2) itself is not complicated -- the dispatcher exists to handle
 * /etc/vfstab, mnttab bookkeeping and per-filesystem argument parsing, none of
 * which is needed to answer "does this filesystem mount at all".
 *
 * The MS_OPTIONSTR contract is easy to get wrong: `optptr` is used for both
 * input and output. The kernel writes the filesystem's canonical option string
 * back into that same buffer, so it must be writable and it must be big enough
 * (MAX_MNTOPT_STR) or the mount fails with EOVERFLOW having done nothing.
 * A string literal here would be a segfault, and a short buffer a confusing
 * errno.
 */

#include <sys/mount.h>
#include <sys/mntent.h>
#include <sys/types.h>

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>

int
main(int argc, char **argv)
{
	/*
	 * MAX_MNTOPT_STR (sys/mntent.h) is what mount(8) itself uses for this
	 * buffer. Anything smaller risks EOVERFLOW on the way *out*, when the
	 * kernel writes back a longer canonical option string than we passed
	 * in -- which is easy to hit, since filesystems tend to spell out
	 * every default.
	 */
	char optbuf[MAX_MNTOPT_STR];
	const char *fstype, *special, *dir;
	int flags = MS_OPTIONSTR;
	int i;

	optbuf[0] = '\0';

	if (argc < 4) {
		(void) fprintf(stderr,
		    "usage: %s <fstype> <special> <dir> [-o options] [-r]\n"
		    "   eg: %s virtiofs store /mnt/store\n",
		    argv[0], argv[0]);
		return (2);
	}

	fstype = argv[1];
	special = argv[2];
	dir = argv[3];

	for (i = 4; i < argc; i++) {
		if (strcmp(argv[i], "-o") == 0 && i + 1 < argc) {
			if (strlcpy(optbuf, argv[++i], sizeof (optbuf)) >=
			    sizeof (optbuf)) {
				(void) fprintf(stderr,
				    "%s: option string too long\n", argv[0]);
				return (2);
			}
		} else if (strcmp(argv[i], "-r") == 0) {
			flags |= MS_RDONLY;
		} else {
			(void) fprintf(stderr, "%s: unknown argument '%s'\n",
			    argv[0], argv[i]);
			return (2);
		}
	}

	/*
	 * MS_DATA says "there is fs-specific data at dataptr"; we pass none,
	 * so it is deliberately absent. virtiofs takes its tag as the *special*
	 * argument rather than through fs-specific data, which is why this
	 * generic tool can mount it at all.
	 */
	if (mount(special, dir, flags, (char *)fstype, NULL, 0,
	    optbuf, sizeof (optbuf)) != 0) {
		(void) fprintf(stderr, "%s: mount %s %s on %s failed: %s\n",
		    argv[0], fstype, special, dir, strerror(errno));
		return (1);
	}

	/*
	 * Print what the kernel handed back, not what we asked for: this is the
	 * filesystem's own view of the mount, and it is the quickest way to see
	 * whether an option was accepted, ignored or silently rewritten.
	 */
	(void) printf("mounted %s (%s) on %s [%s]\n",
	    special, fstype, dir, optbuf);
	return (0);
}
