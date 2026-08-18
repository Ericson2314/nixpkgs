{
  lib,
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

  # `tools/cw/Makefile` hardcodes `NATIVECC= gcc` to get out of its own
  # bootstrap problem, and that bare name does not resolve in a cross stdenv.
  # Point it at `$CC` instead.
  #
  # Nothing here needs to say "build-host program". cw is only ever consumed
  # through `nativeBuildInputs`, and the illumos scope splices, so the instance
  # that gets built there is already the build-platform one and its `$CC` is
  # already the build compiler. `$CC_FOR_BUILD` was asking for what we had.
  #
  # This goes through makeFlagsArray rather than makeFlags so the *shell*
  # expands `$CC`. In makeFlags it would reach make unexpanded, and make would
  # read `$C` as a macro reference and pass the leftover `C`.
  preBuild = ''
    makeFlagsArray+=("NATIVECC=$CC")
  '';

  nativeBuildInputs = [
    illumosSetupHook
    make
  ];

  # `$out/bin/i386`, not just `$out/bin`. `tools/cw/Makefile` installs via
  # `$(ROOTONBLDMACHPROG)` = `$(ROOTONBLD)/bin/$(MACH)/cw`, and it overrides
  # `INS.file` to `$(RM) $@; $(CP) $< $(@D); $(CHMOD) $(FILEMODE) $@`. With the
  # destination directory absent, `$(CP) $< $(@D)` does not fail -- it writes a
  # regular FILE named `i386`. The `chmod` on the next line is then the thing
  # that reports the failure, as
  #
  #     $out/bin/i386 -- "Not a directory"
  #
  # which reads like a MACH-substitution bug and is not one: MACH=i386 is
  # correct throughout.
  #
  # Upstream never trips over this because `$(ROOTONBLDBINMACH)` is created by
  # the `DOROOTDIRS` target in `tools/Makefile`, and we deliberately replace
  # that whole proto-area layout with `$out` (see the comment on
  # `nativeBuildMakeFlags` in mkDerivation.nix). Replacing the layout also
  # means inheriting the job of creating its directories, per package.
  #
  # Any other package installing through `ROOTONBLDMACHPROG` or
  # `ROOTONBLDMACHSHFILES` has the same hole.
  preInstall = ''
    mkdir -p $out/bin/i386 $man/man/man1
  '';

  meta.platforms = lib.platforms.unix;
}
