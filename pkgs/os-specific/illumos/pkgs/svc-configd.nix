{
  lib,
  mkDerivation,
  buildPackages,

  cw,

  libsqlite,
  libbsm,
  libsecdb,
  libumem,
  libuutil,
  libscf,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libsocket,
  libnsl,
  libmd,
  libmp,
  libtsol,
  libinetutil,
  libgen,
  libsmbios,
  libnvpair,
  libdevinfo,
  libsec,
  libavl,
  libidmap,
}:

let
  runtimeLibs = [
    libsqlite
    libbsm
    libsecdb
    libumem
    libuutil
    libscf
    libsocket
    libnsl
    libmd
    libmp
    libtsol
    libinetutil
    libgen
    libsmbios
    libnvpair
    libdevinfo
    libsec
    libavl
    libidmap
  ];
  linkPaths = builtins.toString (
    map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# svc.configd -- the SMF repository server.
#
# This is the other half of libscf: every `scf_handle_bind()` is a door call to
# this daemon, which owns the repository database and is the only thing that
# ever touches it. It is what makes `svccfg validate` more than a parse.
#
# Why it is needed for validation at all, which is not obvious: `svccfg
# validate <file>` reads the manifest with no handle -- `lscf_validate_file()`
# does not bind -- but then hands the parsed bundle to `tmpl_validate_bundle()`,
# and that calls `lscf_prep_hndl()` at `cmd/svc/svccfg/svccfg_tmpl.c:4017`
# before checking anything. Template validation *composes* the manifest's
# property groups against the templates already in the repository, so it needs
# a repository to compose against. Without a server, `svccfg validate` gets no
# further than "Could not connect to repository server".
#
# The store is SQLite 2, from `illumos.libsqlite` -- see that package for why
# the system sqlite cannot stand in.
mkDerivation {
  pname = "svc-configd";
  path = "usr/src/cmd/svc/configd";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # `CPPFLAGS += -I$(SRC)/common/svc`: the repository wire protocol
    # (repcache_protocol.h) and the manifest-hash helpers are shared with
    # libscf and svccfg.
    "usr/src/common/svc"

    # `CPPFLAGS += -I../common`: configd.h includes <configd_exit.h>, the
    # exit-code contract svc.startd reads when the daemon dies, which lives
    # with the other shared svc bits rather than in configd's own directory.
    "usr/src/cmd/svc/common"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [
    cw
  ];

  buildInputs = [
    libsqlite
    libbsm
    libsecdb
    libumem
    libuutil
    libscf
    libnvpair
  ];

  # `-I$(ROOT)/usr/include/sqlite-sys` in the package Makefile resolves to a
  # bare `/usr/include/sqlite-sys` once `ROOT` is empty, so libsqlite's own
  # include directory has to be named here. The header is included as
  # <sqlite.h>, so it is that directory and not its parent that goes on the
  # path.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${libsqlite.dev}/include/sqlite-sys")
    makeFlagsArray+=("LDFLAGS.cmd=${linkPaths}")
  '';

  makeFlags = [
    "MACH=i386"
    "MACH64=amd64"

    # cmd/svc/configd has no amd64 subdirectory -- upstream still builds it
    # 32-bit -- so the macros `Makefile.cmd.64` would have set are passed on
    # the command line instead, exactly as svccfg.nix and getent.nix do.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    # The link goes through the compiler driver, hence GNU ld; see getent.nix
    # for why `LDCHECKS` has to be emptied, and svccfg.nix for `MAPFILES`.
    "LDCHECKS="
    "MAPFILES="
  ];

  # svc.configd installs to `$(ROOTLIBSVCBIN)`, i.e. `$(ROOT)/lib/svc/bin`
  # (cmd/Makefile.cmd:46). `illumosSetupHook`'s `fixIllumosInstallDirs`
  # rewrites /usr/include, /usr/bin and /usr/lib but not this, so redirect the
  # one macro rather than changing the shared hook.
  #
  # The path matters at run time, not just here: svccfg starts a private
  # server from `est->sc_repo_server`, which defaults to the literal
  # "/lib/svc/bin/svc.configd" (`svccfg_engine.c`), overridable with
  # SVCCFG_CONFIGD_PATH.
  installFlags = [ "ROOTLIBSVCBIN=${builtins.placeholder "out"}/lib/svc/bin" ];

  # `$(INS.file)` will not create the destination directory itself. The
  # `restore_repository` script installs beside the daemon.
  preInstall = ''
    mkdir -p $out/lib/svc/bin $out/var/svc
  '';

  meta.mainProgram = "svc.configd";
}
