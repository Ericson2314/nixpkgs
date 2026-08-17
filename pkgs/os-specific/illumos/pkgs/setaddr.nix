{
  lib,
  mkDerivation,

  headers,
  libsocket,
  libnsl,
}:

# setaddr(1) -- put an IPv4 address on a plumbed interface.
#
# Not an illumos program: a few dozen lines written here, for the same reason
# as `klog` and `ditree`. Both packaged tools fail before they reach the
# kernel, for unrelated reasons, and neither failure is about the interface:
#
#   * ifconfig(8) resolves its address argument through the name service
#     switch. `in_getaddr()` has no numeric fast path at all -- it calls
#     getipnodebyname(str, AF_INET, 0, ...) directly -- and the `hosts`
#     backend does not work here, though `passwd` does through the same
#     nss_files.so.1. So every form fails identically:
#
#         ifconfig: 10.0.2.15: bad address
#         ifconfig: 10.0.2.15/24: bad address
#
#   * ipadm(8) parses correctly, through getaddrinfo(), but wants the
#     interface to be its own. One plumbed by ifconfig has no address object,
#     so `create-addr` fails in its own bookkeeping:
#
#         ipadm: Error in setting local address: Operation failed
#
# The ioctls underneath are SIOCSLIFNETMASK, SIOCSLIFADDR and SIOCSLIFFLAGS,
# and inet_pton(3SOCKET) parses the arguments without consulting anything.
# Retire this as soon as either real tool works -- it is a bring-up crutch,
# not a design.
mkDerivation {
  pname = "setaddr";
  noLibc = false;

  # No illumos source subtree; the C is here. `path` still has to name
  # something in the gate for the shared mkDerivation plumbing.
  path = "usr/src/lib/libsocket";

  buildInputs = [
    headers
    libsocket
    libnsl
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -o setaddr ${./setaddr.c} -lsocket -lnsl
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp setaddr $out/bin/setaddr
    chmod 755 $out/bin/setaddr
    runHook postInstall
  '';

  meta = {
    description = "Set an IPv4 address on an illumos interface, without a name service";
    mainProgram = "setaddr";
  };
}
