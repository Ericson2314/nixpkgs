{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
}:

# libxnet.so.1 -- a standard filter on libc.so.1. It contains no code at all:
# `common/mapfile-vers` lists the X/Open networking interfaces and marks each
# one FILTER libc.so.1, so the runtime linker redirects every binding straight
# to libc. The library exists only so that `cc -lxnet`, as XPG demands, keeps
# working after those symbols were folded into libc.
#
# Packaged because it is part of the sockets/XTI surface the networking
# commands are built against; without it a `-lxnet` in any consumer's LDLIBS
# fails outright.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libxnet/amd64";
  pname = "libxnet";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libxnet is a root-filesystem library, i.e.
    # /lib rather than /usr/lib.
    "usr/src/lib/Makefile.rootfs"
    # The amd64 Makefile is driven entirely by these two: filter.com supplies
    # LIBS/DYNFLAGS and pulls in the $(MAPFILE.FLT) filter mapfile, filter.targ
    # replaces `BUILD.SO` with a bare `$(LD)` link that has no objects and adds
    # no .init/.fini.
    "usr/src/lib/Makefile.filter.com"
    "usr/src/lib/Makefile.filter.targ"
    "usr/src/lib/libxnet"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # No `BUILD.SO` override here, unlike every other library in this directory:
  # Makefile.filter.targ already defines it as a direct `$(LD)` call, and with
  # no objects and no LDLIBS there is nothing to point a `-L` at.

  # No headers: the X/Open declarations this filter serves live in the ordinary
  # <sys/socket.h> and <xti.h>, and lib/libxnet has no HDRS of its own.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libxnet.so.1 "$out/lib/"
    ln -s libxnet.so.1 "$out/lib/libxnet.so"

    runHook postInstall
  '';
}
