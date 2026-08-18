{
  lib,
  buildPackages,
  mkDerivation,

  cw,

  libxml2,
  libscf,
  libl,
  libuutil,
  libumem,
  libmd,
  libnvpair,
  libtecla,
  # The DT_NEEDEDs of the above, transitively; the compiler driver's -L path
  # has to be able to resolve them.
  libgen,
  libsmbios,
  libdevinfo,
  libsec,
  libavl,
  libidmap,
  libnsl,
  libmp,
}:

# svccfg(1M) -- the SMF repository editor, and the reason the rest of this
# chain exists.
#
# The interesting subcommand off an illumos machine is `svccfg validate`.
# Unlike `xmllint --dtdvalid`, which only says a manifest is well-formed
# against the service-bundle DTD, `validate` runs the manifest through
# `lxml_get_bundle_file` and then `tmpl_validate_bundle`, i.e. libscf's
# template engine: property groups are checked against the types their
# templates declare, required properties must be present, cardinalities and
# value constraints are enforced, and FMRIs have to parse. None of that is
# expressible in a DTD.
#
# `validate` does need a repository server, which an earlier version of this
# comment denied. `lscf_validate_file()` itself never binds -- that much is
# true -- but it hands the parsed bundle to `tmpl_validate_bundle()`, and that
# calls `lscf_prep_hndl()` at `cmd/svc/svccfg/svccfg_tmpl.c:4017` before
# checking anything, because composing a manifest against its templates means
# composing it against the templates already in the repository. With no server
# reachable, `svccfg validate <file>` stops at "Could not connect to repository
# server". `illumos.svc-configd` is that server; point `SVCCFG_REPOSITORY` at a
# writable path and svccfg forks a private one for the duration
# (`start_private_repository`, svccfg_libscf.c:763).
#
# Note also what the template pass is worth against an *empty* repository:
# very little. Composition has nothing to compose against, so a manifest whose
# dependency names a syntactically invalid FMRI still validates clean. Real
# semantic checking needs a seeded repository.
#
# The parse half does run without any of that, and is worth having on its own:
# `SVCCFG_DTD` (read at `svccfg_xml.c:3721`) points at the DTD shipped in this
# package, so DTD validation works out of a Nix store path with no /usr/share
# -- it catches undeclared elements and bad property types -- and `svccfg
# inventory <file>` runs the full `lxml_get_bundle` parse with no handle at
# all, printing the instance FMRIs it composed.
mkDerivation {
  pname = "svccfg";
  path = "usr/src/cmd/svc/svccfg";

  # Its makefiles index source, object or install directories by $(MACH) /
  # $(MACH64), so it needs the illumos spelling of the CPU. Not the default:
  # setting MACH for a package whose install rules do not expect it relocates
  # that package's output. See `machMakeFlags` in mkDerivation.nix.
  illumosMach = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # `manifest_find.o`, `manifest_hash.o` and `notify_params.o` are compiled
    # out of $(COMDIR).
    "usr/src/cmd/svc/common"

    # Shipped as the manifest DTD; see the header comment.
    "usr/src/cmd/svc/dtd"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [
    cw
    buildPackages.illumos.lex
    buildPackages.illumos.yacc
  ];

  buildInputs = [
    libxml2
    libscf
    libl
    libuutil
    libumem
    libmd
    libnvpair
    libtecla

    # Not linked directly, but GNU ld follows a shared object's own
    # `DT_NEEDED` list and insists on resolving those too, so libscf's and
    # libsmbios' dependencies have to be on the -L path as well.
    libgen
    libsmbios
    libdevinfo
    libsec
    libavl
    libidmap
    libnsl
    libmp
  ];

  # `-L` is not enough for the indirect dependencies. GNU ld looks up a shared
  # object's own `DT_NEEDED` entries along the *runtime* search path --
  # `-rpath-link`, `-rpath`, `DT_RUNPATH` -- and not along `-L`, so linking
  # `-lscf` failed with
  #
  #     libscf.so: undefined reference to `mkdirp@SUNW_1.1'
  #     libscf.so: undefined reference to `smbios_open@SUNWprivate_1.1'
  #
  # even with libgen and libsmbios sitting in `buildInputs`. `-rpath` rather
  # than `-rpath-link` because the answer is wanted at run time too: nothing
  # puts these libraries on the default `/lib:/usr/lib` search path of a
  # Nix-built system, so the binary has to record where they are.
  env.NIX_LDFLAGS = builtins.toString (
    map (p: "-rpath ${lib.getLib p}/lib") [
      libxml2
      libscf
      libl
      libuutil
      libumem
      libmd
      libnvpair
      libtecla
      libgen
      libsmbios
      libdevinfo
      libsec
      libavl
      libidmap
      libnsl
      libmp
    ]
  );

  # `svccfg_xml.c` includes <sasl/saslutil.h> and then never uses anything
  # from it -- no `sasl_*` symbol appears anywhere in cmd/svc, and the Makefile
  # does not link `-lsasl`. On illumos the header is there because Cyrus SASL
  # is in the base system; here it would mean cross-building cyrus_sasl to
  # satisfy a line that contributes nothing. Drop it.
  postPatch = ''
        substituteInPlace usr/src/cmd/svc/svccfg/svccfg_xml.c \
          --replace-fail '#include <sasl/saslutil.h>
    ' ""
  '';

  # See lex.nix and yacc.nix for why both tools need their skeleton
  # directories named explicitly; `Makefile.master` points them at an onbld
  # proto area that does not exist here. Spelled out as
  # `buildPackages.illumos.*` because splicing rewrites `nativeBuildInputs`,
  # not string interpolation.
  #
  # `-I$(ADJUNCT_PROTO)/usr/include/libxml2` in the package Makefile resolves
  # to `/usr/include/libxml2` with no proto area, so libxml2's include
  # directory is named here instead. It has to arrive through `CPPFLAGS.first`
  # rather than as a plain `buildInputs` `-isystem`, because `svccfg.h`
  # includes <libxml/tree.h> by that unprefixed path.
  preBuild = ''
    makeFlagsArray+=("YACC=${buildPackages.illumos.yacc}/bin/yacc -P ${buildPackages.illumos.yacc}/share/lib/ccs/yaccpar")
    makeFlagsArray+=("LEX=${buildPackages.illumos.lex}/bin/lex -Y ${buildPackages.illumos.lex}/share/lib/ccs")
    makeFlagsArray+=("CPPFLAGS.first=-I${libxml2.dev}/include/libxml2")
  '';

  makeFlags = [
    # cmd/svc/svccfg has no amd64 subdirectory -- upstream still builds it
    # 32-bit -- so the macros `Makefile.cmd.64` would have set are passed on
    # the command line instead. See getent.nix, which does the same and
    # explains why this is exactly equivalent to including that fragment.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    # The link goes through the compiler driver, hence GNU ld; see getent.nix
    # for why `LDFLAGS.cmd` and `LDCHECKS` have to be emptied.
    #
    # `MAPOPTS` is the same problem one level up and is specific to this
    # command: `Makefile` adds `$(MAPFILE.LEX)` and `$(MAPFILE.NGB)` to
    # `LDFLAGS` as `-Wl,-M%`, to reduce everything except main() and the `yy*`
    # entry points to local scope. That is symbol hygiene for a program that
    # has a name clash with libl.so.1, not correctness: nothing dlopens
    # svccfg, and GNU ld rejects the syntax outright.
    "LDFLAGS.cmd="
    "LDCHECKS="
    "MAPOPTS="

    # `MAPOPTS` alone is not enough: the mapfiles are also *prerequisites* of
    # the program (`$(PROG): $(OBJS) $(MAPFILES)`), and `$(MAPFILE.NGB)` names
    # `common/mapfiles/gen/i386_gcc_map.noexeglobs`, which is generated by a
    # part of the tree this package does not build.
    "MAPFILES="
  ];

  # svccfg installs to `$(ROOTUSRSBINPROG)`, i.e. `$(ROOT)/usr/sbin/svccfg`.
  # `illumosSetupHook`'s `fixIllumosInstallDirs` rewrites /usr/include,
  # /usr/bin and /usr/lib in every Makefile, but not /usr/sbin -- no packaged
  # command has landed there yet -- so with `ROOT=` empty the install ran
  # against the real `/usr/sbin`. Redirect just this one macro rather than
  # changing the shared hook, which would rebuild the whole tree.
  installFlags = [ "ROOTUSRSBIN=${placeholder "out"}/sbin" ];

  # `$(INS.file)` will not create the destination directory itself.
  preInstall = ''
    mkdir -p $out/sbin
  '';

  # The service-bundle DTD is installed by cmd/svc/dtd's own Makefile, which
  # is not run here. Ship it, since without it `svccfg validate` cannot parse
  # a manifest's external subset unless the host happens to have
  # /usr/share/lib/xml/dtd/service_bundle.dtd.1.
  postInstall = ''
    mkdir -p "$out/share/lib/xml/dtd"
    cp "$SRC/cmd/svc/dtd/service_bundle.dtd.1" "$out/share/lib/xml/dtd/"
  '';

  meta.mainProgram = "svccfg";
}
