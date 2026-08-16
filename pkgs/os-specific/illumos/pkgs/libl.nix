{
  buildPackages,
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
}:

# libl.so.1 -- the lex(1) runtime, `-ll`. Five objects: `yywrap`, `yyless`,
# `reject`, `allprint` and `libmain`, each also built in a wide-character
# (`_w`) and an EUC (`_e`) flavour.
#
# It lives under `cmd/sgs/lex` rather than in `usr/src/lib`, because it is
# built alongside lex itself; the amd64 subdirectory there exists purely to
# produce this 64-bit shared library ("This Makefile is only to produce 64-bit
# lex shared library libl.so.1 and not for building 64-bit lex itself"), and
# its target is `all_lib` rather than `all`.
#
# Packaged because `svccfg` links `-ll`: its command language is a
# lex/yacc pair, and the generated scanner calls `yywrap`.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/cmd/sgs/lex/amd64";
  pname = "libl";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/cmd/sgs/lex"
    "usr/src/cmd/sgs/include"
    # `amd64/Makefile` ends with `include ../../../Makefile.targ`, which from
    # cmd/sgs/lex/amd64 is cmd/Makefile.targ.
    "usr/src/cmd/Makefile.targ"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [ buildPackages.illumos.yacc ];

  buildInputs = [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  # Not `all`: that is lex the program, which is a build-host tool and is
  # already packaged separately (see lex.nix).
  buildFlags = [ "all_lib" ];

  # `Makefile.com:78` assigns `CPPFLAGS` outright rather than appending, so
  # `CPPFLAGS.first` never reaches the compile line and the installed headers
  # have to be named through `CPPFLAGS` itself.
  #
  # See lex.nix for why `YACC` has to be spelled out with `-P`, and libm.nix
  # for why `BUILD.SO` has to call `$(LD)` directly.
  preBuild = ''
    makeFlagsArray+=("YACC=${buildPackages.illumos.yacc}/bin/yacc -P ${buildPackages.illumos.yacc}/share/lib/ccs/yaccpar")
    makeFlagsArray+=("CPPFLAGS=-I${headers}/include \$(INCLIST) \$(DEFLIST) \$(CPPFLAGS.master)")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libl.so.1 "$out/lib/"
    ln -s libl.so.1 "$out/lib/libl.so"

    runHook postInstall
  '';
}
