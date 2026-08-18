{
  lib,
  mkDerivation,

  cw,

  libscf,
  libuutil,
  libcontract,
  # The DT_NEEDEDs of the above, transitively; GNU ld resolves a shared
  # object's own `DT_NEEDED` list along the runtime search path, so libscf's
  # dependencies have to be reachable too. See svccfg.nix for the long form.
  libumem,
  libmd,
  libnvpair,
  libgen,
  libsmbios,
  libdevinfo,
  libsec,
  libavl,
  libidmap,
  libnsl,
  libmp,
}:

# svcadm(1M) -- the verb half of SMF, i.e. the `systemctl enable/disable/
# restart/refresh` of illumos. `svccfg` can import and export manifests, but
# only svcadm can change an instance's *administrative* state at run time:
#
#   svcadm enable  [-rst] FMRI     set general/enabled, optionally recursively
#   svcadm disable [-st]  FMRI
#   svcadm restart        FMRI     stop then start, via a restarter event
#   svcadm refresh        FMRI     re-read configuration without restarting
#   svcadm clear          FMRI     take an instance out of maintenance
#   svcadm milestone      FMRI     move the system's run level
#
# All of it is done by writing to the repository (libscf) and letting
# svc.startd notice; svcadm itself never talks to a restarter directly. The
# `-s` flag is the exception that needs the third library: it waits for the
# instance to reach the requested state, and `synch.c` does that by watching
# the process contract the restarter created, which is `libcontract`.
#
# Dependency-wise this is by far the cheapest of the SMF commands -- `-lscf
# -luutil -lcontract` and nothing else, all three already packaged. `svcs`,
# the query half, is the expensive one: it also links `-lzonecfg`, which
# pulls in libbrand, libuuid, libdlpi and libdladm.
mkDerivation {
  pname = "svcadm";
  path = "usr/src/cmd/svc/svcadm";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    libscf
    libuutil
    libcontract

    libumem
    libmd
    libnvpair
    libgen
    libsmbios
    libdevinfo
    libsec
    libavl
    libidmap
    libnsl
    libmp
  ];

  # `-L` is not enough for the indirect dependencies, and `-rpath` rather than
  # `-rpath-link` because the answer is wanted at run time as well: nothing
  # puts these on a Nix-built system's default `/lib:/usr/lib` search path.
  # Every `-L` needs a matching `-R`, or the library drops out of both the
  # runpath and the Nix closure; `-zignore` prunes the entries that turn out
  # to be unused. See svccfg.nix.
  env.NIX_LDFLAGS = builtins.toString (
    map (p: "-rpath ${lib.getLib p}/lib") [
      libscf
      libuutil
      libcontract
      libumem
      libmd
      libnvpair
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

  makeFlags = [
    # cmd/svc/svcadm has no amd64 subdirectory -- upstream builds it 32-bit --
    # so the macros `Makefile.cmd.64` would have set are passed on the command
    # line instead, exactly as svccfg.nix and getent.nix do.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    # The link goes through the compiler driver, hence GNU ld; see getent.nix
    # for why `LDFLAGS.cmd` and `LDCHECKS` have to be emptied, and svccfg.nix
    # for `MAPFILES`.
    "LDFLAGS.cmd="
    "LDCHECKS="
    "MAPFILES="
  ];

  # svcadm installs to `$(ROOTUSRSBINPROG)`. `illumosSetupHook`'s
  # `fixIllumosInstallDirs` does not rewrite /usr/sbin, so redirect the macro
  # here rather than changing the shared hook. Same as svccfg.nix.
  installFlags = [ "ROOTUSRSBIN=${placeholder "out"}/sbin" ];

  preInstall = ''
    mkdir -p $out/sbin
  '';

  meta.mainProgram = "svcadm";
}
