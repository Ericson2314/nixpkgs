{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libgen,
  libinetutil,
  libdlpi,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path. libdlpi drags
  # in the whole libdladm closure -- see libdladm.nix for what each entry is.
  libdladm,
  libdevinfo,
  libsocket,
  libscf,
  librcm,
  libnvpair,
  libexacct,
  libkstat,
  libpool,
  libvarpd,
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
    libgen
    libinetutil
    libdlpi
    libdladm
    libdevinfo
    libsocket
    libscf
    librcm
    libnvpair
    libexacct
    libkstat
    libpool
    libvarpd
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

# libdhcputil.so.1 -- the DHCP option table and packet-scanning code shared by
# everything on the DHCP path: `dhcp_inittab.c` reads /etc/dhcp/inittab and
# tells a caller the type and arity of each option code, `dhcp_symbol.c`
# converts option values to and from text, `dhcpmsg.c` is the common logging
# entry point, and `scan.c` (out of common/net/dhcp, shared with the kernel's
# DHCP client) walks a packet's option area.
#
# It is here for `libdhcpagent`, which links it, and thence for `ifconfig`,
# whose `ifconfig net0 dhcp` subcommand talks to dhcpagent(8). Nothing in the
# static-address path touches it, but the link needs it either way.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdhcputil/amd64";
  pname = "libdhcputil";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libdhcputil is a /lib library, because
    # ifconfig and dhcpagent both live in the root filesystem.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdhcputil"

    # `scan.o` is not built from lib/libdhcputil at all: `COMDIR` points at
    # the DHCP code shared with the kernel, and Makefile.com has an explicit
    # pics rule for it. <dhcp_impl.h> and <dhcp_symbol_common.h> live there
    # too and are part of the library's public header set.
    "usr/src/common/net/dhcp"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libgen
    libinetutil
    libdlpi
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # <libgen.h>, <libinetutil.h> and <libdlpi.h> are angle-bracket includes
  # that upstream resolves out of the proto area, so the corresponding `dev`
  # outputs go on the include path explicitly. libnvpair's and libkstat's come
  # with libdlpi's, because <libdlpi.h>'s neighbours in libdladm's header set
  # pull them in.
  #
  # libdhcputil's *own* headers need naming too: Makefile.com adds only
  # `-I$(COMDIR)` for the shared DHCP directory and never an `-I` for
  # `SRCDIR`, so `dhcp_inittab.h`'s `#include <dhcp_symbol.h>` would only ever
  # have resolved through the proto area.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libgen.dev}/include -I${libinetutil.dev}/include -I${libdlpi.dev}/include -I${libnvpair.dev}/include -I${libkstat.dev}/include -I\$(SRC)/lib/libdhcputil/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # The header set is the *top* lib/libdhcputil Makefile's `HDRS`, which is
  # `LOCHDRS` out of common plus `COMHDRS` out of common/net/dhcp. That
  # Makefile is the one we do not run: the amd64 subdirectory is built
  # directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdhcputil.so.1 "$out/lib/"
    ln -s libdhcputil.so.1 "$out/lib/libdhcputil.so"

    mkdir -p "$dev/include"
    cp ../common/dhcp_inittab.h ../common/dhcp_symbol.h ../common/dhcpmsg.h \
      "$dev/include/"
    cp ../../../common/net/dhcp/dhcp_impl.h \
      ../../../common/net/dhcp/dhcp_symbol_common.h "$dev/include/"

    runHook postInstall
  '';
}
