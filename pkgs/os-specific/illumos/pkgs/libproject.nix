{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libsecdb,
  libproc,
  libpool,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  sgs-libelf,
  sgs-librtld_db,
  libctf,
  libsaveargs,
  libdisasm,
  libdwarf,
  libscf,
  libnvpair,
  libexacct,
  libxml2,
  libgen,
  libsmbios,
  libuutil,
  libdevinfo,
  libsec,
  libavl,
  libidmap,
  libnsl,
  libmd,
  libmp,
  zlib,
}:

let
  runtimeLibs = [
    libsecdb
    libproc
    libpool
    sgs-libelf
    sgs-librtld_db
    libctf
    libsaveargs
    libdisasm
    libdwarf
    libscf
    libnvpair
    libexacct
    libxml2.out
    libgen
    libsmbios
    libuutil
    libdevinfo
    libsec
    libavl
    libidmap
    libnsl
    libmd
    libmp
    zlib
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libproject.so.1 -- the project(4) database interface: `getprojent` and
# friends, plus `setproject()`, which puts a process into a project and
# applies that project's resource controls and pool binding.
#
# Projects are not configured in this VM. libproject is here because
# `librestart` links `-lproject` -- a service method runs in the project named
# by its `method_context`, and `restarter_set_method_context()` calls
# `setproject()` to get there -- and `svc.startd` links `-lrestart`. With no
# project database, the call fails and startd falls back to running the method
# without one.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libproject/amd64";
  pname = "libproject";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libproject"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libsecdb
    libproc
    libpool
    # Header-only: <libproc.h> includes <libctf.h>, which includes
    # <gelf.h> from libelf.
    libctf
    sgs-libelf
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) ${linkPaths} \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o \$(LDLIBS)")
  '';

  # <project.h> lives in usr/src/head and already comes from the `headers`
  # package, so there is nothing to install but the library itself.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libproject.so.1 "$out/lib/"
    ln -s libproject.so.1 "$out/lib/libproject.so"

    runHook postInstall
  '';
}
