/*
 * klog -- print the kernel messages that nothing else on this system can show.
 *
 * illumos does not keep a kernel ring buffer that userland can just read the
 * way dmesg(1) reads /dev/kmsg on Linux. cmn_err(9F) output goes two places:
 * to the console driver, and to the STREAMS log driver, log(4D). Anything the
 * kernel prints *before* a console logger registers is held on log(4D)'s
 * queue, and is delivered to the first process that registers -- so the early
 * boot messages are still there to be read, but only by a program that speaks
 * the log driver protocol. If nothing ever registers, they are simply never
 * seen, which is why an attach(9E) failure during boot looks like silence.
 *
 * syslogd(8) is that program on a real system, but it wants a config file, a
 * writable /var, a door, and several threads. This is the twenty lines of it
 * that matter during bring-up: register as the console logger, drain whatever
 * the kernel has queued, and print it.
 *
 * The protocol is from cmd/syslogd/syslogd.c: open the device, send an
 * I_CONSLOG through I_STR to declare ourselves the console logger, then
 * getmsg(2) in a loop -- the control part is a struct log_ctl (level, flags,
 * timestamps) and the data part is the message text.
 *
 * Exits after `-t` seconds with no new message (default 3), so it can be run
 * in the background of a probe script and reaped without a signal:
 *
 *     klog -t 5 > /tmp/klog.out &
 *     ditree              # forces an attach, provoking the failure
 *     wait; cat /tmp/klog.out
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
#include <stropts.h>
#include <sys/strlog.h>

#define	KLOG_MAXLINE	4096

/*
 * /dev/log is what syslogd opens, but /dev is populated by devfsadm, which
 * during bring-up may not have run -- and the whole point of this program is
 * to diagnose a system that is not fully up. So fall back to the devfs path,
 * which the kernel creates itself and which is always present.
 */
static const char *devpaths[] = {
	"/dev/log",
	"/devices/pseudo/log@0:log",
	"/devices/pseudo/log@0:conslog",
	NULL
};

static const char *
levelname(int level)
{
	static const char *names[] = {
		"emerg", "alert", "crit", "err",
		"warn", "notice", "info", "debug"
	};

	if (level < 0 || level > 7)
		return ("?");
	return (names[level]);
}

static int
openklog(void)
{
	int i, fd;
	struct strioctl str;

	for (i = 0; devpaths[i] != NULL; i++) {
		if ((fd = open(devpaths[i], O_RDONLY)) < 0)
			continue;

		/*
		 * Declare ourselves the console logger. Without this the
		 * driver hands us syslog traffic only, and the cmn_err(9F)
		 * output we are after -- which is what a failing attach
		 * prints -- never arrives.
		 */
		str.ic_cmd = I_CONSLOG;
		str.ic_timout = 0;
		str.ic_len = 0;
		str.ic_dp = NULL;
		if (ioctl(fd, I_STR, &str) < 0) {
			(void) fprintf(stderr,
			    "klog: %s: I_CONSLOG failed: %s\n",
			    devpaths[i], strerror(errno));
			(void) close(fd);
			continue;
		}

		(void) fprintf(stderr, "klog: reading %s\n", devpaths[i]);
		return (fd);
	}

	(void) fprintf(stderr, "klog: no usable log device\n");
	return (-1);
}

int
main(int argc, char **argv)
{
	int fd, c, quiet_ms = 3000;
	long nmsg = 0;

	while ((c = getopt(argc, argv, "t:")) != -1) {
		switch (c) {
		case 't':
			quiet_ms = atoi(optarg) * 1000;
			break;
		default:
			(void) fprintf(stderr,
			    "usage: klog [-t quiet-seconds]\n");
			return (2);
		}
	}

	if ((fd = openklog()) < 0)
		return (1);

	for (;;) {
		struct pollfd pfd;
		struct strbuf ctl, dat;
		struct log_ctl hdr;
		char buf[KLOG_MAXLINE + 1];
		int flags = 0;

		pfd.fd = fd;
		pfd.events = POLLIN;
		pfd.revents = 0;

		/*
		 * Stop after a quiet period rather than reading forever: the
		 * queued backlog arrives in a burst, and once it stops there
		 * is nothing more to wait for in a one-shot probe.
		 */
		if (poll(&pfd, 1, quiet_ms) <= 0)
			break;

		ctl.maxlen = sizeof (struct log_ctl);
		ctl.len = 0;
		ctl.buf = (caddr_t)&hdr;
		dat.maxlen = KLOG_MAXLINE;
		dat.len = 0;
		dat.buf = buf;

		if (getmsg(fd, &ctl, &dat, &flags) < 0) {
			if (errno == EINTR)
				continue;
			(void) fprintf(stderr, "klog: getmsg: %s\n",
			    strerror(errno));
			break;
		}

		if (dat.len <= 0)
			continue;

		buf[dat.len] = '\0';

		/*
		 * The kernel's text usually carries its own newline; do not
		 * add a second one, so multi-line panics stay readable.
		 */
		(void) printf("[%7ld] %-6s %s%s",
		    (long)hdr.ltime, levelname(hdr.level), buf,
		    buf[dat.len - 1] == '\n' ? "" : "\n");
		(void) fflush(stdout);
		nmsg++;
	}

	(void) fprintf(stderr, "klog: %ld message(s)\n", nmsg);
	(void) close(fd);
	return (0);
}
