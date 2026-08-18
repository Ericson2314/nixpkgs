{
  lib,
  mkDerivation,

  cw,

  libcontract,
  libscf,
  libuutil,
  libumem,
  libnvpair,
  libproc,
  # The DT_NEEDEDs of the above, transitively; GNU ld resolves a shared
  # object's own `DT_NEEDED` list along the runtime search path rather than
  # along `-L`, so libscf's and libproc's dependencies have to be reachable
  # too. See svccfg.nix for the long form.
  libmd,
  libgen,
  libsmbios,
  libdevinfo,
  libsec,
  libavl,
  libidmap,
  libnsl,
  libmp,
  sgs-libelf,
  sgs-librtld_db,
  libctf,
  libsaveargs,
  libdisasm,
}:

# svcs(1) -- the query half of SMF, i.e. `systemctl status` and
# `systemctl list-units`. With `svcadm` it completes the pair that makes SMF
# usable interactively rather than merely running:
#
#   svcs                 list enabled instances and their states
#   svcs -a              ... including disabled ones
#   svcs -l FMRI         the long form: state, next state, restarter, contract,
#                        dependencies, log file
#   svcs -x              explain why services are not running -- this is the
#                        genuinely good one, and has no systemd equivalent;
#                        `explain.c` walks the dependency graph backwards from
#                        each impaired instance to the root cause
#   svcs -p FMRI         the processes in the instance's contract (libproc)
#   svcs -L / -Lv FMRI   the instance's log file / its contents
#
# `-lzonecfg` is patched out; see patches/0019 for the full reasoning. In
# short: it is linked for one cosmetic call, `zone_get_rootpath()` at
# `svcs.c:477`, and it would otherwise require building libbrand, librcm,
# libvarpd, libdladm, libdlpi and libuuid first. Everything else zone-shaped
# in svcs comes from libc and <zone.h>. That patch is a bring-up shim and is
# expected to be retired when libdladm gets built for `dladm`/`ipadm`.
#
# Note what this cannot do yet, so that an empty listing is not mistaken for a
# packaging fault: `svc.configd` currently exits 102 (database initialization
# failure), so there is no repository to read and svcs will say so rather than
# report anything.
mkDerivation {
  pname = "svcs";
  path = "usr/src/cmd/svc/svcs";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # `notify_params.o` is `$(MYOBJS)`, compiled out of `../common`; the
    # Makefile also puts that directory on `CPPFLAGS`.
    "usr/src/cmd/svc/common"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    libcontract
    libscf
    libuutil
    libumem
    libnvpair
    libproc

    libmd
    libgen
    libsmbios
    libdevinfo
    libsec
    libavl
    libidmap
    libnsl
    libmp
    sgs-libelf
    sgs-librtld_db
    libctf
    libsaveargs
    libdisasm
  ];

  # Every `-L` needs a matching `-R` or the library drops out of both
  # `DT_RUNPATH` and the Nix closure -- and so out of the boot archive.
  # Over-supplying is safe: `-zignore` prunes the entries no `DT_NEEDED`
  # actually uses.
  env.NIX_LDFLAGS = builtins.toString (
    map (p: "-rpath ${lib.getLib p}/lib") [
      libcontract
      libscf
      libuutil
      libumem
      libnvpair
      libproc
      libmd
      libgen
      libsmbios
      libdevinfo
      libsec
      libavl
      libidmap
      libnsl
      libmp
      sgs-libelf
      sgs-librtld_db
      libctf
      libsaveargs
      libdisasm
    ]
  );

  makeFlags = [
    # cmd/svc/svcs has no amd64 subdirectory -- upstream builds it 32-bit --
    # so the macros `Makefile.cmd.64` would have set are passed on the command
    # line instead, exactly as svccfg.nix, svcadm.nix and getent.nix do.
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

  # svcs installs to `$(ROOTPROG)`, i.e. `$(ROOTBIN)/svcs`, and the setup hook
  # has already rewritten `$(ROOT)/usr/bin` to `$(BINDIR)` -- unlike svcadm,
  # which lands in /usr/sbin and needs the macro redirected. The directory
  # still has to exist before `$(INS.file)` runs.
  preInstall = ''
    mkdir -p $out/bin
  '';

  meta.mainProgram = "svcs";
}
