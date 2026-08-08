{
  lib,
  mkDerivation,

  buildPackages,
}:

# genoffsets(1ONBLD): the driver half of $(OFFSETS_CREATE). It splits an
# `offsets.in` file into a C stub and a ctfstabs script, compiles the stub,
# runs ctfconvert(1) over it, and feeds the result to ctfstabs(1).
#
# usr/src/tools/scripts/Makefile is deliberately not used. Its only rule for
# this file is Makefile.master's `.pl` suffix rule -- a TEXT_DOMAIN
# substitution this script has no occurrence of, plus chmod +x, keeping the
# `#!/bin/perl` shebang, which is not a path that exists here -- and building
# that directory as a whole would drag in the thirty-odd other scripts along
# with ksh93 and python. Install the one script and fix its interpreter.
mkDerivation {
  pname = "genoffsets";
  noCC = true;

  path = "usr/src/tools/scripts/genoffsets.pl";

  dontBuild = true;

  # `path` is a file, so the setup hook's `cd $COMPONENT_PATH` does not fire and
  # there is no makefile to run.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    substitute usr/src/tools/scripts/genoffsets.pl $out/bin/genoffsets \
      --replace-fail '#!/bin/perl' '#!${buildPackages.perl}/bin/perl'
    chmod +x $out/bin/genoffsets

    runHook postInstall
  '';

  # This script runs on the machine doing the build, not on the target, so it
  # is the build perl that has to be on the shebang line. genoffsets only uses
  # core modules (File::Basename, Getopt::Std, POSIX).
  depsBuildBuild = [ buildPackages.perl ];

  meta.platforms = lib.platforms.unix;
}
