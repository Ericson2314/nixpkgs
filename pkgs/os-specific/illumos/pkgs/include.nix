{
  mkDerivation,

  source,
  fetchpatch,

  illumosSetupHook,
  make,
  install,
  rpcgen,
  #mtree,
  #pax,
  buildPackages,
}:
mkDerivation {
  name = "include";
  path = "usr/src/head";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    #"lib"
    ##"sys"
    #"sys/arch"
    ## LDIRS from the mmakefile
    #"sys/crypto"
    #"sys/ddb"
    #"sys/dev"
    #"sys/isofs"
    #"sys/miscfs"
    #"sys/msdosfs"
    #"sys/net"
    #"sys/netinet"
    #"sys/netinet6"
    #"sys/netmpls"
    #"sys/net80211"
    #"sys/nfs"
    #"sys/ntfs"
    #"sys/scsi"
    #"sys/sys"
    #"sys/ufs"
    #"sys/uvm"
  ];

  patches = [
    (fetchpatch {
      name = "linux-support.patch";
      url = "https://github.com/illumos/illumos-gate/compare/${source.rev}...Ericson2314:illumos-gate:headers-hack.diff";
      hash = "sha256-fCp2blv+2fgcM7ldWCJPCM4NQXAUkL7Kw7AQKJjtFrI=";
    })
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    #mtree
    #pax
    rpcgen
  ];

  #makeFlags = [
  #  "RPCGEN_CPP=${buildPackages.stdenv.cc.cc}/bin/cpp"
  #  "-B"
  #];

  headersOnly = true;
}
