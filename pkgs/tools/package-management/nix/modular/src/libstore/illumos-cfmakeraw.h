/*
 * cfmakeraw(3) for illumos.
 *
 * cfmakeraw is a BSD extension that glibc and the BSDs provide but POSIX does
 * not, and illumos has never picked it up -- it is in neither <termios.h> nor
 * libc. nix's unix/build/derivation-builder.cc calls it when setting up the
 * build sandbox's pty:
 *
 *   derivation-builder.cc:980:5: error: 'cfmakeraw' was not declared in this
 *   scope
 *
 * This is force-included (-include) for that component rather than patched in,
 * because the nix components share one source tree.
 *
 * The body is the standard definition, as documented by termios(3) on the BSDs
 * and cfmakeraw(3) in glibc. Every flag it touches exists on illumos.
 */

#ifndef NIX_ILLUMOS_CFMAKERAW_H
#define NIX_ILLUMOS_CFMAKERAW_H

#include <termios.h>

static inline void cfmakeraw(struct termios *t)
{
    t->c_iflag &= ~(IMAXBEL | IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    t->c_oflag &= ~OPOST;
    t->c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    t->c_cflag &= ~(CSIZE | PARENB);
    t->c_cflag |= CS8;
    t->c_cc[VMIN] = 1;
    t->c_cc[VTIME] = 0;
}

#endif /* NIX_ILLUMOS_CFMAKERAW_H */
