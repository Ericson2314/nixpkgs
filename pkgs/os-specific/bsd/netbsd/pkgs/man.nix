{ mkDerivation, defaultMakeFlags }:

mkDerivation {
  path = "share/man";
  noCC = true;
  # `share/man` ships no headers, and its subdirectory Makefiles have no
  # `includes` target for the default hook to call.
  skipIncludesPhase = true;
  # man0 generates a man.pdf using ps2pdf, but doesn't install it later,
  # so we can avoid the dependency on ghostscript
  postPatch = ''
    substituteInPlace $COMPONENT_PATH/man0/Makefile --replace "ps2pdf" "echo noop "
    # `safer.tmac` no longer exists as of groff 1.23: safer mode became the
    # default, and `-msafer` survives only as a no-op alias on the `groff`
    # front end. This pipeline reaches `troff` directly, which still tries to
    # open the macro file and dies with "cannot open macro file named in '-m'
    # command-line argument 'safer'". Dropping the flag keeps the old meaning.
    substituteInPlace $COMPONENT_PATH/man0/Makefile --replace-fail "-Z -msafer -man" "-Z -man"
  '';
  makeFlags = defaultMakeFlags ++ [
    "FILESDIR=$(out)/share"
    "MKRUMP=no" # would require to have additional path sys/rump/share/man
  ];
}
