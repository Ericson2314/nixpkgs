{
  mkDerivation,

  cw,

  libcontract,
  libkstat,
  libmd5,
  libnvpair,
  librestart,
  libscf,
  libsysevent,
  libumem,
  libuutil,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libpool,
  libproject,
  libsecdb,
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
    libkstat
    libmd5
    libnvpair
    librestart
    libscf
    libsysevent
    libumem
    libuutil
    libpool
    libproject
    libsecdb
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
  linkPaths = builtins.toString (map (p: "-L${p}/lib -R${p}/lib") runtimeLibs);
in

# svc.startd -- the SMF master restarter, and the thing that actually starts a
# service.
#
# It is two halves. The *graph engine* reads the repository through libscf,
# builds the dependency graph over every instance, and decides what may run;
# the *restarter* half executes methods, each in a process contract
# (`libcontract`) so that startd learns when the whole process tree exits
# rather than just the method's first process. Instances delegated to another
# restarter are handed off over the protocol in `librestart`.
#
# Built 64-bit the same way svccfg and svc.configd are, by passing the macros
# `Makefile.cmd.64` would have set: cmd/svc/startd has no amd64 directory
# because upstream builds it 32-bit.
#
# It is linked without libbe and libfmevent; see patches/0016 and the
# SMF_HAVE_LIBBE / SMF_HAVE_LIBFMEVENT guards in graph.c for why that is
# equivalent to failure paths the code already supports.
mkDerivation {
  pname = "svc-startd";
  path = "usr/src/cmd/svc/startd";

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

    # `manifest_hash.o` is compiled out of $(COMDIR), and `definit.o` out of
    # the shared default/init parser.
    "usr/src/cmd/svc/common"
    "usr/src/common/definit"
    "usr/src/common/svc"

    "usr/src/common/mapfiles"

    # `restarter.xml`; see `postInstall`.
    "usr/src/cmd/svc/milestone/restarter.xml"
  ];

  extraNativeBuildInputs = [
    cw
  ];

  buildInputs = [
    libcontract
    libkstat
    libmd5
    libnvpair
    librestart
    libscf
    libsysevent
    libumem
    libuutil
    # Header-only, reached through <librestart.h> and <libproc.h>.
    libproc
    libctf
    sgs-libelf
    libpool
    libproject
    libsecdb
  ];

  preBuild = ''
    makeFlagsArray+=("LDFLAGS.cmd=${linkPaths}")
  '';

  makeFlags = [
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
    "CTFMERGE_HOOK="
  ];

  # svc.startd installs to `$(ROOTLIBSVCBIN)`, i.e. `$(ROOT)/lib/svc/bin`
  # (cmd/Makefile.cmd:46), beside svc.configd. `illumosSetupHook`'s
  # `fixIllumosInstallDirs` rewrites /usr/include, /usr/bin and /usr/lib but
  # not this, so redirect the one macro.
  installFlags = [ "ROOTLIBSVCBIN=${builtins.placeholder "out"}/lib/svc/bin" ];

  preInstall = ''
    mkdir -p $out/lib/svc/bin
  '';

  # svc.startd is the master restarter, but the *service* that represents it,
  # `svc:/system/svc/restarter:default`, is a repository object like any other
  # and has to be imported from a manifest. startd creates it implicitly on a
  # writable root; on a read-only one it never appears, and then
  # `svcadm disable -s` / `enable -s` fail with
  # `Restarter for instance "..." is unavailable`, because the synchronous path
  # resolves an instance's restarter through the repository.
  #
  # Upstream installs this from cmd/svc/milestone, whose makefile builds a
  # great deal we do not, so take the single file. The build runs in the
  # package's own directory, so the sibling is reached relatively; `install`
  # here is illumos' own and has no `-D`.
  postInstall = ''
    mkdir -p $out/lib/svc/manifest/system/svc
    cp ../milestone/restarter.xml \
      $out/lib/svc/manifest/system/svc/restarter.xml
    chmod 0444 $out/lib/svc/manifest/system/svc/restarter.xml
  '';

  meta.mainProgram = "svc.startd";
}
