{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  nawk,
  rpcgen,
  buildPackages,
}:

# Every header directory under uts/common that has an install_h target.
#
# These are all installed by a real illumos build (they end up under
# /usr/include), so packaging them is preferable to patching the headers that
# include them. In particular `vm` is here: sys/vnode.h and friends include
# <vm/seg_enum.h>, and illumos installs vm/ precisely so that works.
let
  dirs = [
    "c2"
    "des"
    "fs"
    "gssapi"
    "idmap"
    "inet"
    "ipp"
    "klm"
    "net"
    "netinet"
    "nfs"
    "rpc"
    "rpcsvc"
    "sharefs"
    "smb"
    "smbsrv"
    "sys"
    "vm"
  ];
in

mkDerivation {
  name = "uts-headers";
  path = "usr/src/uts/common";

  # Its makefiles index source, object or install directories by $(MACH) /
  # $(MACH64), so it needs the illumos spelling of the CPU. Not the default:
  # setting MACH for a package whose install rules do not expect it relocates
  # that package's output. See `machMakeFlags` in mkDerivation.nix.
  illumosMach = true;
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/Makefile.psm"

    "usr/src/uts/Makefile.uts"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    nawk
    rpcgen
  ];

  dontBuild = true;

  # Several of these Makefiles install arch-specific headers from $(MACH)_HDRS,
  # and on x86 illumos' MACH is "i386" -- not uname's "x86_64", which would
  # leave those lists empty and silently omit headers.
  makeFlags = [
  ];

  # NetBSD's rpcgen shells out to a C preprocessor, defaulting to a /usr/bin
  # path that does not exist here. It then emits only boilerplate and still
  # exits 0, so the generated headers come out nearly empty and the failure
  # only surfaces much later as a missing type (rpc/rpcb_clnt.h wanting
  # `rpcblist`, which the generated rpcb_prot.h should define).
  # It also has to be a *traditional* cpp: rpcgen passes `%`-escaped lines
  # through verbatim, and a modern cpp expands __STDC__ inside them, turning
  # `#ifdef __STDC__` into `#ifdef 1`.
  env.RPCGEN_CPP = buildPackages.writeShellScript "rpcgen-cpp" ''
    exec ${buildPackages.stdenv.cc}/bin/cpp -traditional-cpp -U__STDC__ "$@"
  '';

  # uts/common itself has no Makefile driving the subdirectories, so run
  # install_h in each of them.
  installPhase = ''
    runHook preInstall

  ''
  # `concatTo` rather than a bare `$makeFlags`: under `__structuredAttrs`
  # (set in mkDerivation.nix) makeFlags is a real bash array, so word-
  # splitting a scalar would pass only its first element -- INCLUDEDIR
  # arrived empty and install(1) tried to create /bsm.
  + ''
    local flagsArray=()
    concatTo flagsArray makeFlags makeFlagsArray

    for d in ${lib.concatStringsSep " " dirs}; do
      echo "installing headers from $d"
      ( cd "$d" && make "''${flagsArray[@]}" install_h )
    done

    runHook postInstall
  '';
}
