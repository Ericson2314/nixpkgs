/*
 * setaddr -- put an IPv4 address on a plumbed interface, and nothing else.
 *
 * This exists because both packaged tools fail before reaching the kernel,
 * for unrelated reasons, and neither failure is about the interface:
 *
 *   * ifconfig(8) resolves its address argument with getipnodebyname() --
 *     in_getaddr() has no numeric fast path at all -- so a literal dotted
 *     quad goes through the name service switch. The `hosts` backend does
 *     not work here (though `passwd` does, through the same nss_files.so.1),
 *     so every form fails identically: "10.0.2.15: bad address".
 *
 *   * ipadm(8) parses fine, via getaddrinfo(), but wants the interface to be
 *     its own: an interface plumbed by ifconfig has no address object, and
 *     `create-addr` fails in its bookkeeping with "Error in setting local
 *     address: Operation failed".
 *
 * The ioctls underneath are three lines. This does those three lines, with
 * inet_pton(3SOCKET) for parsing so that no name service is involved, and is
 * meant to be retired the moment either tool works.
 *
 *     setaddr vioif0 10.0.2.15 255.255.255.0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/sockio.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <netinet/in.h>
#include <arpa/inet.h>

/*
 * The SIOC*LIF* forms rather than the older SIOC*IF*: the latter carry a
 * struct ifreq whose sockaddr has no room for anything but IPv4 and whose
 * name field is IFNAMSIZ, and illumos has deprecated them. lifreq is what
 * ifconfig and libipadm both use.
 */
static int
set_sockaddr(int s, const char *ifname, int cmd, const struct in_addr *addr,
    const char *what)
{
	struct lifreq lifr;
	struct sockaddr_in *sin;

	(void) memset(&lifr, 0, sizeof (lifr));
	(void) strncpy(lifr.lifr_name, ifname, sizeof (lifr.lifr_name) - 1);

	sin = (struct sockaddr_in *)&lifr.lifr_addr;
	sin->sin_family = AF_INET;
	sin->sin_addr = *addr;

	if (ioctl(s, cmd, &lifr) < 0) {
		(void) fprintf(stderr, "setaddr: %s: %s\n", what,
		    strerror(errno));
		return (-1);
	}
	return (0);
}

int
main(int argc, char **argv)
{
	int s;
	struct in_addr addr, mask;
	struct lifreq lifr;

	if (argc != 4) {
		(void) fprintf(stderr,
		    "usage: setaddr <interface> <address> <netmask>\n");
		return (2);
	}

	if (inet_pton(AF_INET, argv[2], &addr) != 1) {
		(void) fprintf(stderr, "setaddr: %s: not an IPv4 address\n",
		    argv[2]);
		return (2);
	}
	if (inet_pton(AF_INET, argv[3], &mask) != 1) {
		(void) fprintf(stderr, "setaddr: %s: not an IPv4 netmask\n",
		    argv[3]);
		return (2);
	}

	if ((s = socket(AF_INET, SOCK_DGRAM, 0)) < 0) {
		(void) fprintf(stderr, "setaddr: socket: %s\n",
		    strerror(errno));
		(void) fprintf(stderr,
		    "setaddr: (has soconfig(8) run? without the sock2path\n"
		    "         mappings loaded, AF_INET sockets cannot be\n"
		    "         created at all)\n");
		return (1);
	}

	/*
	 * Netmask first. Setting the address derives a default classful mask
	 * and, on an interface that is already up, can bring the route table
	 * along with it; doing the mask first means the address lands with
	 * the prefix already correct.
	 */
	if (set_sockaddr(s, argv[1], SIOCSLIFNETMASK, &mask,
	    "SIOCSLIFNETMASK") != 0)
		return (1);
	if (set_sockaddr(s, argv[1], SIOCSLIFADDR, &addr, "SIOCSLIFADDR") != 0)
		return (1);

	/* And up. */
	(void) memset(&lifr, 0, sizeof (lifr));
	(void) strncpy(lifr.lifr_name, argv[1], sizeof (lifr.lifr_name) - 1);
	if (ioctl(s, SIOCGLIFFLAGS, &lifr) < 0) {
		(void) fprintf(stderr, "setaddr: SIOCGLIFFLAGS: %s\n",
		    strerror(errno));
		return (1);
	}
	lifr.lifr_flags |= IFF_UP;
	if (ioctl(s, SIOCSLIFFLAGS, &lifr) < 0) {
		(void) fprintf(stderr, "setaddr: SIOCSLIFFLAGS: %s\n",
		    strerror(errno));
		return (1);
	}

	(void) printf("setaddr: %s = %s/%s, up\n", argv[1], argv[2], argv[3]);
	(void) close(s);
	return (0);
}
