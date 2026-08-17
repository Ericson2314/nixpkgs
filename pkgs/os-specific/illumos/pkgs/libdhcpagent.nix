{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libsocket,
  libdhcputil,
  libuuid,
  libdlpi,
  libcontract,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path. libdlpi drags
  # in the whole libdladm closure -- see libdladm.nix for what each entry is.
  libdladm,
  libinetutil,
  libdevinfo,
  libscf,
  librcm,
  libnvpair,
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
    libsocket
    libdhcputil
    libuuid
    libdlpi
    libcontract
    libdladm
    libinetutil
    libdevinfo
    libscf
    librcm
    libnvpair
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

# libdhcpagent.so.1 -- the *client* side of dhcpagent(8): the IPC protocol a
# program uses to ask the agent to start, extend, release or inspect a DHCP
# lease on an interface (`dhcpagent_ipc.c`), the helper that starts the agent
# on demand (`dhcpagent_util.c`), and the /etc/dhcp hostconf and stable-DUID
# files (`dhcp_hostconf.c`, `dhcp_stable.c`).
#
# It is packaged because `ifconfig` links `-ldhcpagent` for its `dhcp`
# subcommand, and `libipadm` links it for `ipadm create-addr -T dhcp`. Neither
# the daemon nor a DHCP-configured interface exists in this VM -- the address
# is assigned statically -- but the link needs the library regardless, and
# packaging the real one is cheaper than reasoning about a stub for a protocol
# with this much surface.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdhcpagent/amd64";
  pname = "libdhcpagent";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libdhcpagent is a /lib library, since ifconfig
    # lives in /sbin.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdhcpagent"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libsocket
    libdhcputil
    libuuid
    libdlpi
    libcontract
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # The `dev` outputs named here supply the angle-bracket includes upstream
  # would have found in the proto area: <dhcp_impl.h>/<dhcp_inittab.h> from
  # libdhcputil, <libdlpi.h>, and <libcontract.h>/<libcontract_priv.h> (the
  # agent is started under a process contract). libnvpair's and libkstat's
  # ride along with libdlpi's, whose header set reaches libdladm's.
  #
  # libdhcpagent's own headers need naming too: Makefile.com adds no `-I` for
  # `SRCDIR`, so `dhcpagent_util.c`'s `#include <dhcpagent_ipc.h>` would only
  # ever have resolved through the proto area.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libdhcputil.dev}/include -I${libdlpi.dev}/include -I${libcontract.dev}/include -I${libnvpair.dev}/include -I${libkstat.dev}/include -I\$(SRC)/lib/libdhcpagent/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # The four headers are the *top* lib/libdhcpagent Makefile's `HDRS`, which
  # we do not run: the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdhcpagent.so.1 "$out/lib/"
    ln -s libdhcpagent.so.1 "$out/lib/libdhcpagent.so"

    mkdir -p "$dev/include"
    cp ../common/dhcp_hostconf.h ../common/dhcpagent_ipc.h \
      ../common/dhcpagent_util.h ../common/dhcp_stable.h "$dev/include/"

    runHook postInstall
  '';
}
