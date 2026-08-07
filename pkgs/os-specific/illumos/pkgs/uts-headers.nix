{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  nawk,
  rpcgen,
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

  # uts/common itself has no Makefile driving the subdirectories, so run
  # install_h in each of them.
  installPhase = ''
    runHook preInstall

    for d in ${lib.concatStringsSep " " dirs}; do
      echo "installing headers from $d"
      ( cd "$d" && make $makeFlags install_h )
    done

    runHook postInstall
  '';
}
