{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
}:

# illumos' own yacc, built out of `usr/src/tools/yacc`. That directory vendors
# no code: it is a Makefile that compiles `usr/src/cmd/sgs/yacc/common` --
# the same sources the shipped yacc is built from -- with the native toolchain,
# which is how a cross-build of illumos gets a yacc it can run.
#
# Deliberately not called `yacc-native`, even though it only ever runs on the
# build host: that is what `nativeBuildInputs` and splicing are for, and it is
# how `make`, `install` and `cw` are already named here. `ld` carries
# its suffix only to tell it apart from `sgs-ld`, the target-platform build of
# the same sources; there is no target-side yacc in this scope.
#
# `Makefile.master:128` points YACC at `$(ONBLD_TOOLS)/bin/$(MACH)/yacc -P
# $(ONBLD_TOOLS)/share/lib/ccs/yaccpar`. The grammars in the gate are written
# against AT&T yacc's skeleton layout: `lib/libsec/common/acl.y` calls
# `bad_entry_type` from three actions and defines it `static` in the epilogue,
# which only compiles because AT&T yacc emits the epilogue *before* including
# `yaccpar` -- so `yyparse`, and the action switch inside it, comes after the
# definition. (That one is fixed in the gate anyway; it is cited here as the
# kind of thing this tool exists to keep working.)
#
# `yaccpar` is installed alongside the binary because the `-P` argument is not
# optional: the generated parser `#include`s it.
mkDerivation {
  pname = "yacc";

  path = "usr/src/tools/yacc";
  extraPaths = [
    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"
    "usr/src/cmd/sgs/yacc/common"
    "usr/src/cmd/sgs/include"
    "usr/src/Makefile.master"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
  ];

  buildFlags = [ "all" ];

  # Upstream's `install` target puts the binary under
  # `$(ROOTONBLD)/bin/$(MACH)`, where MACH is `uname -p` on the build host --
  # a proto-area layout that buys us nothing in a store path. Place both files
  # by hand instead, so consumers can name them without knowing the host arch.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/lib/ccs"
    cp yacc "$out/bin/yacc"
    cp "$SRC/cmd/sgs/yacc/common/yaccpar" "$out/share/lib/ccs/yaccpar"

    runHook postInstall
  '';

  meta.platforms = lib.platforms.unix;
}
