{
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  rpcgen,
  buildPackages,
}:
mkDerivation {
  name = "head";
  path = "usr/src/head";
  noCC = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    install
    make
    rpcgen
  ];

  # NetBSD's rpcgen shells out to a C preprocessor, defaulting to a
  # /usr/bin path that does not exist here. It then emits only boilerplate and
  # still exits 0, so the generated headers come out nearly empty and the
  # failure only surfaces much later as missing types.
  # It also has to be a *traditional* cpp: rpcgen passes `%`-escaped lines
  # through verbatim, and a modern cpp expands __STDC__ inside them, turning
  # `#ifdef __STDC__` into `#ifdef 1`.
  env.RPCGEN_CPP = buildPackages.writeShellScript "rpcgen-cpp" ''
    exec ${buildPackages.stdenv.cc}/bin/cpp -traditional-cpp -U__STDC__ "$@"
  '';

  # head/Makefile installs arch-specific headers from $(MACH)_HDRS, and on x86
  # illumos' MACH is "i386" -- not uname's "x86_64", which would leave the list
  # empty and silently omit e.g. <stack_unwind.h>.
  makeFlags = [
    "MACH=i386"
    "MACH64=amd64"
  ];

  headersOnly = true;
}
