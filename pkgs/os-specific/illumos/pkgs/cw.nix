{
  lib,
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
}:

mkDerivation {
  pname = "cw";

  path = "usr/src/tools/cw";
  extraPaths = [
    "usr/src/tools/Makefile"
    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

  ];

  outputs = [
    "out"
    "man"
  ];

  # cw's x86 argument-mapping tables (-xarch=, -xmodel=kernel, -Wu,-save_args)
  # are guarded on `__x86`, a Studio-only predefined macro, so they compile out
  # entirely when cw itself is built by gcc on Linux -- and cw then *errors* on
  # those flags rather than ignoring them.
  #
  # That is fixed at the source now: the guards accept __i386__/__x86_64__ as
  # well (see the `tools/cw` commit on nix-cross). The source is the right place
  # for it, because the guards describe the architecture cw *targets*, not the
  # one it happens to be compiled on -- a distinction the original code did not
  # need to make while everything was native.

  makeFlags = [
    "ROOTONBLD=${builtins.placeholder "out"}"
    "ROOTONBLDMAN1ONBLD=${builtins.placeholder "man"}/man/man1"
  ];

  # cw is a *build-host* program: it wraps the compiler that produces target
  # objects, but is itself run on the build machine. `tools/cw/Makefile` sets
  # `NATIVECC= gcc`, and the cross stdenv offers only
  # `x86_64-unknown-solaris2.11-gcc`, so that bare name does not resolve.
  #
  # This goes through makeFlagsArray rather than makeFlags so the *shell*
  # expands $CC_FOR_BUILD. In makeFlags it would reach make unexpanded, and make
  # would read `$C` as a macro reference and pass the leftover `C_FOR_BUILD`.
  preBuild = ''
    makeFlagsArray+=("NATIVECC=$CC_FOR_BUILD")
  '';

  nativeBuildInputs = [
    illumosSetupHook
    make
  ];

  # Supplies $CC_FOR_BUILD, as ctfconvert/ctfmerge/ctfstabs already do for their
  # own build-host helpers.
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  preInstall = ''
    mkdir -p $out/bin $man/man/man1
  '';

  meta.platforms = lib.platforms.unix;
}
