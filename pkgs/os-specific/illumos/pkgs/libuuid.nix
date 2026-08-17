{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libsocket,
  libnsl,
  libdlpi,
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
  libmd,
  libmp,
}:

let
  runtimeLibs = [
    libsocket
    libnsl
    libdlpi
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

# libuuid.so.1 -- DCE/RFC 4122 universally unique identifiers: `uuid_generate`
# and the parse/unparse/compare helpers. The `-ldlpi` and `-lsocket`/`-lnsl`
# dependencies are not decoration: a time-based (version 1) UUID embeds a MAC
# address, and `etheraddr.c` gets one by walking the datalinks with
# `dlpi_walk`.
#
# Packaged for `libdhcpagent`, which links `-luuid` to build the DHCP client
# identifier, and thence for `ifconfig`.
#
# Unlike most of the libraries here this needs no `dev` output: its public
# header is <uuid/uuid.h>, which lives in usr/src/head and so is already in
# the `headers` package rather than under lib/libuuid.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libuuid/amd64";
  pname = "libuuid";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libuuid is a /lib library.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libuuid"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libsocket
    libnsl
    libdlpi
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # <libdlpi.h> is an angle-bracket include resolved out of the proto area
  # upstream, so libdlpi's `dev` output is named here; libnvpair's and
  # libkstat's come with it, since libdlpi's header set reaches libdladm's,
  # which includes both.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libdlpi.dev}/include -I${libnvpair.dev}/include -I${libkstat.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libuuid.so.1 "$out/lib/"
    ln -s libuuid.so.1 "$out/lib/libuuid.so"

    runHook postInstall
  '';
}
