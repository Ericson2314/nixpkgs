{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libcontract,
  libpool,
  libproject,
  libsecdb,
  libnvpair,
  libsysevent,
  libscf,
  libuutil,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libproc,
  sgs-libelf,
  sgs-librtld_db,
  libctf,
  libsaveargs,
  libdisasm,
  libdwarf,
  libexacct,
  libxml2,
  libgen,
  libsmbios,
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
    libcontract
    libpool
    libproject
    libsecdb
    libnvpair
    libsysevent
    libscf
    libuutil
    libproc
    sgs-libelf
    sgs-librtld_db
    libctf
    libsaveargs
    libdisasm
    libdwarf
    libexacct
    libxml2.out
    libgen
    libsmbios
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
    [ "-L${libcMinimal}/lib" "-L${libssp_ns}/lib" ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# librestart.so.1 -- the library every SMF *restarter* is written against, and
# the last rung below `svc.startd`.
#
# It is the other half of the restarter protocol: `restarter_bind_handle()`
# subscribes a restarter to the events svc.startd's graph engine sends it, and
# `restarter_store_contract`/`restarter_remove_contract` track the process
# contracts a running instance owns. The piece that pulls in most of this
# dependency list is `restarter_set_method_context()`, which assembles the
# credentials a service method runs under -- user, group, privileges,
# project (`-lproject`), resource pool (`-lpool`) and security attributes
# (`-lsecdb`) -- from the instance's `method_context`.
#
# None of project, pool or the security databases is configured in this VM;
# each lookup fails and the method runs without it, which is the behaviour a
# service with a bare `method_credential` already gets.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/librestart/amd64";
  pname = "librestart";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/librestart"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libcontract
    libpool
    libproject
    libsecdb
    libnvpair
    libsysevent
    libscf
    libuutil
    # Header-only, by way of <libproc.h> and <libctf.h>.
    libproc
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
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/librestart/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) ${linkPaths} \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o \$(LDLIBS)")
  '';

  # <librestart.h> and <librestart_priv.h> are installed into /usr/include by
  # the *top* lib/librestart Makefile, which we do not run: we build the amd64
  # subdirectory directly. svc.startd needs both.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp librestart.so.1 "$out/lib/"
    ln -s librestart.so.1 "$out/lib/librestart.so"

    mkdir -p "$dev/include"
    cp ../common/librestart.h ../common/librestart_priv.h "$dev/include/"

    runHook postInstall
  '';
}
