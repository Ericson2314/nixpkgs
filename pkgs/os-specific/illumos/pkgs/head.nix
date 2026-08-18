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

  headersOnly = true;
}
