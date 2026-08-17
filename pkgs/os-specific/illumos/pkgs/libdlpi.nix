{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libinetutil,
  libdladm,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path. This is
  # libdladm's whole closure -- see libdladm.nix for what each of them is.
  libdevinfo,
  libsocket,
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
    libinetutil
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

# libdlpi.so.1 -- the DLPI (Data Link Provider Interface) client library: the
# supported way for a userland program to open a datalink as a STREAMS device
# and send or receive raw link-layer frames. `dlpi_open`/`dlpi_bind`/
# `dlpi_send`/`dlpi_recv` wrap the DL_* message exchange, and `dlpi_walk`
# enumerates the links (which is where the `-ldladm` dependency comes in).
#
# Packaged because `ifconfig` links `-ldlpi` -- it needs the link-layer
# address of an interface to plumb it -- and because libipadm and
# libdhcpagent both do too; DHCP in particular is raw-frame work before there
# is an address to send from.
#
# The direction of the libdladm dependency is worth noting, since the two
# libraries look mutually recursive at first glance: libdlpi links libdladm,
# libdladm merely *includes* <libdlpi.h> for the DLPI type constants. See
# libdladm.nix, which takes that header out of this source directory.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdlpi/amd64";
  pname = "libdlpi";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libdlpi is a /lib library, since ifconfig
    # lives in /sbin and must work before /usr is mounted.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdlpi"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libinetutil
    libdladm
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # <libinetutil.h> (for the interface-name helpers) and <libdladm.h>/
  # <libdllink.h> (for `dlpi_walk`'s link enumeration) are angle-bracket
  # includes that upstream resolves out of the proto area, so the two `dev`
  # outputs go on the include path explicitly, ahead of the `-I../common`
  # Makefile.com adds for libdlpi's own headers. libnvpair's and libkstat's
  # come along because <libdladm.h> itself includes <libnvpair.h> and
  # <kstat.h> -- link properties are nvlists and link statistics are kstats --
  # so anything including libdladm's headers needs those two as well.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libinetutil.dev}/include -I${libdladm.dev}/include -I${libnvpair.dev}/include -I${libkstat.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # <libdlpi.h> is the *top* lib/libdlpi Makefile's whole `HDRS`, and that
  # Makefile is the one we do not run: the amd64 subdirectory is built
  # directly. `libdlpi_impl.h` is not in upstream's install list, so it is not
  # copied here either.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdlpi.so.1 "$out/lib/"
    ln -s libdlpi.so.1 "$out/lib/libdlpi.so"

    mkdir -p "$dev/include"
    cp ../common/libdlpi.h "$dev/include/"

    runHook postInstall
  '';
}
