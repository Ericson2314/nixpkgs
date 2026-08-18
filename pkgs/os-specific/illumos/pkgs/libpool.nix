{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libscf,
  libnvpair,
  libexacct,
  libxml2,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
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
}:

let
  runtimeLibs = [
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
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libpool.so.1 -- the resource pools configuration library: the `pool_conf_*`
# interface over pool/processor-set configurations, with two backends, a
# kernel one (`pool_kernel.c`, talking to /dev/pool) and an XML one
# (`pool_xml.c`, over libxml2) for static configuration files.
#
# Pools are not configured in this VM and never will be for this bring-up.
# libpool is here because `libproject` links `-lpool` and `librestart` links
# `-lproject`, and `svc.startd` links `-lrestart` -- startd consults project
# and pool bindings when it launches a method, and degrades gracefully when
# neither is configured.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libpool/amd64";
  pname = "libpool";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libpool"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libscf
    libnvpair
    libexacct
    libxml2
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # `-I$(ADJUNCT_PROTO)/usr/include/libxml2` resolves to a bare
  # /usr/include/libxml2 with no proto area, so libxml2's include directory is
  # named here instead -- the same thing svccfg.nix has to do, and for the
  # same reason: pool_xml.c includes <libxml/parser.h> by that unprefixed
  # path.
  #
  # The search paths go *before* `$(DYNFLAGS)` here, unlike everywhere else:
  # libpool puts `-lxml2` in DYNFLAGS rather than LDLIBS (Makefile.com:41-43
  # explains why -- a lint artefact), and the illumos link-editor resolves
  # `-l` against the `-L`s seen so far, so a trailing -L is too late.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libxml2.dev}/include/libxml2 -I\$(SRC)/lib/libpool/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) ${linkPaths} \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o \$(LDLIBS)")
  '';

  # <pool.h> is installed into /usr/include by the *top* lib/libpool Makefile,
  # which we do not run: we build the amd64 subdirectory directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libpool.so.1 "$out/lib/"
    ln -s libpool.so.1 "$out/lib/libpool.so"

    mkdir -p "$dev/include"
    cp ../common/pool.h "$dev/include/"

    runHook postInstall
  '';
}
