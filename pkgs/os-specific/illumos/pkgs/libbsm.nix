{
  mkDerivation,
  buildPackages,
  nawk,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libsocket,
  libnsl,
  libmd,
  libsecdb,
  libtsol,
  libinetutil,
  libscf,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libmp,
  libgen,
  libsmbios,
  libnvpair,
  libuutil,
  libdevinfo,
  libsec,
  libavl,
  libidmap,
}:

let
  # Every one of these is a DT_NEEDED of libbsm.so.1, directly or transitively,
  # so each gets a -R as well as a -L: a -L is only a link-time search path and
  # leaves nothing in the object, which costs both the DT_RUNPATH and the nix
  # reference -- and without the reference the library never reaches the boot
  # archive at all. libcMinimal and libssp_ns deliberately keep a bare -L; they
  # are the bootstrap libc and must not be pinned at run time.
  runtimeLibs = [
    libsocket
    libnsl
    libmd
    libsecdb
    libtsol
    libinetutil
    libscf
    libmp
    libgen
    libsmbios
    libnvpair
    libuutil
    libdevinfo
    libsec
    libavl
    libidmap
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libbsm.so.1 -- the Basic Security Module library: the audit trail. Two
# interfaces live here, the old `au_*`/`audit_*` record writers and the newer
# `adt_*` session interface that most callers now use.
#
# It is here for `svc.configd`, which links `-lbsm` and calls `adt_*` in
# `client.c` to open an audit session per repository client and record who
# changed what. Auditing is not enabled in this VM -- `adt_audit_state()`
# returns false and the calls become nearly free -- but the symbols have to
# resolve for configd to start at all.
#
# Two source files and one header do not exist until the build makes them, and
# upstream makes them from the *top* lib/libbsm Makefile, which we do not run
# because we build the amd64 leaf directly. See postPatch.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libbsm/amd64";
  pname = "libbsm";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libbsm"

    # au_usermask.c includes the private <nss.h>, which reaches upstream
    # builds only through the proto area.
    "usr/src/lib/libnsl/nss"

    # CPPFLAGS says -I$(AUDITD): audit_plugin.c is written against auditd's
    # own private headers.
    "usr/src/cmd/auditd"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libsocket
    libnsl
    libmd
    libsecdb
    libtsol
    libinetutil
    libscf
    # <libscf.h> opens with #include <libnvpair.h>, so anything that includes
    # it -- audit_scf.c here -- needs libnvpair's headers too.
    libnvpair
  ];

  extraNativeBuildInputs = [
    # mkhdr.sh formats the event table with nawk, and $(AWK) is nawk
    # (Makefile.master:155) rather than gawk.
    nawk
  ];

  # `auditxml` is a perl program run at build time, and it parses adt.xml with
  # XML::Parser -- so this is a build-host perl with that module, not the
  # cross-built one.
  depsBuildBuild = [
    (buildPackages.perl.withPackages (p: [ p.XMLParser ]))
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  # Three generated files, plus a proto-area include directory to put them in.
  # Paths are relative to the source root: `cdIllumosPath` is itself a postPatch
  # hook and hooks run after this, so the cd into `path` has not happened yet.
  #
  #   * audit_uevents.h, from `sh mkhdr.sh` -- an event-number table scraped out
  #     of audit_event.txt. mkhdr.sh calls /usr/bin/date by absolute path,
  #     which does not exist here.
  #
  #   * common/adt_xlate.c and common/adt_event.h, from `perl -I. auditxml`
  #     over common/adt.xml. adt_xlate.o is in OBJECTS, so this is not
  #     optional: without it the library is missing its whole event-translation
  #     table.
  #
  # The headers are then staged under `gen-include/bsm/` together with the
  # hand-written ones from common/, because the sources spell these includes
  # <bsm/adt.h>, <bsm/audit_uevents.h> and so on -- the proto area is where
  # they would normally come from, and the shipped `headers` package has only
  # the uts-side bsm headers, not libbsm's own.
  postPatch = ''
    substituteInPlace usr/src/lib/libbsm/mkhdr.sh \
      --replace-fail /usr/bin/date date

    (
      cd usr/src/lib/libbsm
      sh mkhdr.sh
      perl -I. auditxml -o common common/adt.xml

      mkdir -p gen-include/bsm
      cp audit_uevents.h gen-include/bsm/
      cp common/*.h gen-include/bsm/
    )
  '';

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libbsm/gen-include -I\$(SRC)/lib/libnsl/nss")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # <bsm/libbsm.h> and friends are installed into /usr/include/bsm by the *top*
  # lib/libbsm Makefile, which we do not run. Ship the whole staged directory,
  # generated files included, so a consumer needs only this package.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libbsm.so.1 "$out/lib/"
    ln -s libbsm.so.1 "$out/lib/libbsm.so"

    mkdir -p "$dev/include/bsm"
    cp ../gen-include/bsm/*.h "$dev/include/bsm/"

    runHook postInstall
  '';
}
