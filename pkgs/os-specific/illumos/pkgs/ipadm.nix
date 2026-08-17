{
  lib,
  mkDerivation,

  headers,

  libipadm,
  libofmt,
  libinetutil,
  libnvpair,
  libipmp,
  libcmdutils,
  libxnet,
  libsocket,
  libnsl,
  libdladm,
  libkstat,
  libdlpi,
}:

# ipadm(8) -- the modern illumos interface for IP configuration.
#
# `ifconfig` still exists and still works, but it is the legacy tool: on
# illumos, persistent configuration, address objects and interface properties
# all live in ipadm, and svc:/network/physical drives ipadm rather than
# ifconfig.
#
# Packaged here for a second and more immediate reason: `ifconfig` cannot parse
# an address on this system. `in_getaddr()` (cmd-inet/usr.sbin/ifconfig) has no
# numeric fast path at all -- it goes straight to
#
#     getipnodebyname(str, AF_INET, 0, &error_num)
#
# so a literal dotted quad is resolved through the name service switch, and
# something in the `hosts`/`ipnodes` path is not working here even though the
# same nss_files.so.1 serves `passwd` correctly (`getent passwd root` works;
# `getent hosts localhost` returns nothing). The result is:
#
#     ifconfig: 10.0.2.15: bad address
#
# for every form -- plain, CIDR, and hex netmask alike.
#
# ipadm goes through `getaddrinfo()` (lib/libipadm/common/ipadm_addr.c:1895),
# which parses a numeric address with inet_pton before consulting any backend,
# so it is not affected by that. Which of the two is "right" is a separate
# question -- the hosts lookup should work and is worth fixing -- but this is
# the tool the system is supposed to be configured with regardless.
#
#     ipadm create-addr -T static -a 10.0.2.15/24 vioif0/v4
mkDerivation {
  pname = "ipadm";
  path = "usr/src/cmd/cmd-inet/usr.sbin/ipadm";

  buildInputs = [
    headers
    libipadm
    libofmt
    libinetutil
    libnvpair
    libipmp
    libcmdutils
    libxnet
    libsocket
    libnsl
    libdladm
    libkstat
    libdlpi
  ];

  dontConfigure = true;

  # Compiled directly rather than through the directory makefile: like
  # `soconfig`, that makefile is shared with the wider cmd-inet family and
  # pulls in Makefile.mech_krb5, which is a poor trade for one program. See
  # soconfig.nix for the two consequences of bypassing it (the ROOTFS_PROG
  # 32-bit interpreter pin, which does not arise here, and no CTF).
  #
  # `-lxnet` before `-lsocket`: ipadm uses the XPG socket interfaces, and on
  # illumos those live in libxnet, which must precede libsocket on the link
  # line or the XPG variants are shadowed by the classic ones.
  buildPhase = ''
    runHook preBuild
    $CC -O2 -o ipadm ipadm.c \
      -DTEXT_DOMAIN=\"SUNW_OST_OSCMD\" \
      -Wno-incompatible-pointer-types -Wno-error \
      -lipadm -lofmt -linetutil -lnvpair -lipmp -lcmdutils -lxnet -lsocket -lnsl
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/sbin
    cp ipadm $out/sbin/ipadm
    chmod 755 $out/sbin/ipadm
    runHook postInstall
  '';

  meta = {
    description = "illumos IP administration tool";
    mainProgram = "ipadm";
  };
}
