{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libinetutil,
  libsocket,
  libdlpi,
  libnvpair,
  libdhcpagent,
  libdladm,
  libsecdb,
  libdhcputil,
  libipmp,
  libcmdutils,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path. Most of this is
  # libdladm's closure -- see libdladm.nix for what each entry is -- plus
  # libuuid and libcontract, which arrive through libdhcpagent.
  libuuid,
  libcontract,
  libdevinfo,
  libscf,
  librcm,
  libexacct,
  libkstat,
  libpool,
  libvarpd,
  libgen,
  libsmbios,
  libuutil,
  libsec,
  libavl,
  libidmap,
  libumem,
  libidspace,
  librename,
  libxml2,
  libnsl,
  libmd,
  libmp,
}:

let
  runtimeLibs = [
    libinetutil
    libsocket
    libdlpi
    libnvpair
    libdhcpagent
    libdladm
    libsecdb
    libdhcputil
    libipmp
    libcmdutils
    libuuid
    libcontract
    libdevinfo
    libscf
    librcm
    libexacct
    libkstat
    libpool
    libvarpd
    libgen
    libsmbios
    libuutil
    libsec
    libavl
    libidmap
    libumem
    libidspace
    librename
    libxml2.out
    libnsl
    libmd
    libmp
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libipadm.so.1 -- the IP interface and address administration library, and
# the thing that actually assigns an address. `ipadm_create_if` plumbs an
# interface (the SIOCLIFADDIF/SIOCSLIFNAME dance on /dev/udp), `ipadm_create_addr`
# adds a static, DHCP or auto-configured address to it, and `ipadm_prop.c`
# is the read/write side of the per-interface and per-protocol tunables that
# `ipadm show-prop` reports.
#
# `ifconfig` links `-lipadm` and delegates the real work to it, which makes
# this the last library between a booted illumos VM and a reachable IP
# address. `ipadm` itself (the command) is a thinner wrapper over the same
# entry points and would be worth packaging next.
#
# One caveat about run-time behaviour, since it is not obvious from the link:
# the *persistent* half of libipadm -- everything in `ipadm_persist.c` -- is a
# door client of `ipmgmtd`, the IP management daemon, which is not packaged.
# The volatile operations (`IPADM_OPT_ACTIVE`) go straight to the kernel
# through ioctls and work without it; anything asking for `IPADM_OPT_PERSIST`
# will fail to reach the door. Assigning an address for this bring-up is a
# volatile operation, so that is not in the way.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libipadm/amd64";
  pname = "libipadm";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libipadm is a /lib library, since ifconfig
    # lives in /sbin and must work before /usr is mounted.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libipadm"

    # `libipadm_impl.h` includes <libsocket_priv.h>, which reaches upstream
    # builds only through the proto area -- lib/libsocket's top Makefile
    # installs it into /usr/include -- so take it from the source directory,
    # exactly as libsocket.nix and libinetutil.nix already do.
    "usr/src/lib/libsocket/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libinetutil
    libsocket
    libdlpi
    libnvpair
    libdhcpagent
    libdladm
    libsecdb
    libdhcputil
    libipmp
    libcmdutils
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # Each `dev` output named here supplies headers libipadm includes with angle
  # brackets and that upstream resolves out of the proto area: <libinetutil.h>,
  # <libdlpi.h>, <libdladm.h>/<libdllink.h>/<libdliptun.h>, <ipmp_query.h>,
  # the <dhcpagent_ipc.h>/<dhcpagent_util.h> pair from libdhcpagent and the
  # <dhcp_inittab.h>/<dhcp_symbol.h> pair from libdhcputil. libnvpair's and
  # libkstat's are required by libdladm's own headers in turn.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libinetutil.dev}/include -I${libdlpi.dev}/include -I${libdladm.dev}/include -I${libnvpair.dev}/include -I${libkstat.dev}/include -I${libdhcpagent.dev}/include -I${libdhcputil.dev}/include -I${libipmp.dev}/include -I${libcmdutils.dev}/include -I\$(SRC)/lib/libsocket/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # The three headers are the *top* lib/libipadm Makefile's `HDRS`, which we do
  # not run: the amd64 subdirectory is built directly. `ipadm_ipmgmt.h` is in
  # that list despite naming the private daemon protocol, because ipmgmtd and
  # its clients share the door request structures it declares.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libipadm.so.1 "$out/lib/"
    ln -s libipadm.so.1 "$out/lib/libipadm.so"

    mkdir -p "$dev/include"
    cp ../common/libipadm.h ../common/ipadm_ndpd.h ../common/ipadm_ipmgmt.h \
      "$dev/include/"

    runHook postInstall
  '';
}
