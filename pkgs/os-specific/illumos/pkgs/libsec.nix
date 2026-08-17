{
  buildPackages,
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,
  libavl,
  libidmap,
  libuutil,
  libnsl,
  libnvpair,
  # libnsl.so.1 pulls in libmp/libmd, and the illumos link-editor insists on
  # finding a shared object's own dependencies on the link path.
  libmd,
  libmp,

  # illumos' own AT&T-derived lex and yacc, not flex/bison -- see the comment
  # on the LEX/YACC makeFlags below.
  lex,
  yacc,
}:

# libsec.so.1 -- illumos' ACL library. It is what `acl(2)`/`facl(2)` are
# wrapped in: `acl_get`, `acl_set`, `acl_trivial`, `acl_totext`/`acl_fromtext`,
# `acl_strip`, and the NFSv4-vs-POSIX-draft ACL translation in
# `common/aclmode.c`.
#
# This is the last library `coreutils` needs. gnulib's `file-has-acl.c` has an
# illumos arm guarded by `HAVE_ACL_TRIVIAL`, and configure finds
# `acl_trivial`'s declaration in <sys/acl.h> -- which the headers package
# already ships -- so the arm is compiled unconditionally and the link then
# dies with
#
#     file-has-acl.c:622: undefined reference to `acl_trivial'
#
# `Makefile.com` links `-lc -lavl -lidmap`: the AVL trees back the ACL sorting
# in `common/aclsort.c`, and libidmap converts between SIDs and uid/gids when
# rendering an NFSv4 ACL to text.
#
# The library also has two generated sources -- `acl.y` (the ACL text-format
# grammar) and `acl_lex.l` -- built with illumos' own yacc/lex; see the LEX/YACC
# comment below for why flex is not a substitute here.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libsec/amd64";
  pname = "libsec";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libsec"

    # `acl_common.o` is compiled straight out of the code shared with the
    # kernel, via Makefile.com's `pics/%.o: ../../../common/acl/%.c` rule.
    "usr/src/common/acl"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [
    lex
    yacc
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libidmap
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # `Makefile.com:77` is a multi-target rule -- `acl.tab.c acl.tab.h: acl.y` --
  # and dmake runs it once per target, so `yacc` is invoked twice. Run in
  # parallel, the second invocation truncates `acl.tab.h` while the compile of
  # `acl_lex.c` is reading it, and the tokens defined near the end of the header
  # go missing:
  #
  #     acl_lex.l:97: error: 'USER_TOK' undeclared
  #
  # which reads like a missing include rather than a race. Serialise this
  # package rather than patching upstream's rule.
  enableParallelBuilding = false;

  # `Makefile.master` points YACC and LEX at `$(ONBLD_TOOLS)/bin/$(MACH)/`,
  # illumos' own AT&T-derived yacc and lex. We build those (see lex.nix and
  # yacc.nix) rather than substituting bison/flex, because flex cannot express
  # this scanner: in AT&T lex every character is read through the `input()`
  # macro, and `acl_lex.l` `#undef`s `input`/`unput` and supplies functions that
  # walk an in-memory buffer -- that is how the library parses ACL text from a
  # string rather than from a stream. flex reads via `YY_INPUT` into its own
  # buffer and emits `input` as a real function, so the file does not even
  # compile ("redefinition of 'input'"); and one rule calls `unput()` and then
  # `strdup(yytext)`, which flex's `unput()` clobbers. Silently mis-parsing ACL
  # text is a bad failure mode for a library that decides permissions.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. libidmap's own
  # dependencies (libavl, libuutil, libnsl, libnvpair, and libnsl's libmd and
  # libmp) all have to be on the path too.
  #
  # Both tools need their skeleton files named explicitly, exactly as
  # `Makefile.master:162-163` does: `yacc -P .../yaccpar` and
  # `lex -Y .../share/lib/ccs` (holding ncform/nceucform/nrform). Passing a
  # bare `yacc` compiles fine and then dies at run time with
  #
  #     fatal: cannot find parser /usr/share/lib/ccs/yaccpar
  #
  # since the built-in default is an absolute path that only exists on a real
  # illumos system.
  #
  # These spell out `buildPackages.illumos.*` rather than `${yacc}`/`${lex}`:
  # splicing rewrites `nativeBuildInputs`, not string interpolation, so a bare
  # `${yacc}` would name the *target*-platform build. Both spellings appear on
  # purpose -- the argument for the dependency, the explicit path for the
  # string. See lex.nix, which does the same for its own yacc.
  #
  # They go through `makeFlagsArray` rather than `makeFlags` because they
  # contain spaces, and `makeFlags` entries are word-split.
  preBuild = ''
    makeFlagsArray+=("YACC=${buildPackages.illumos.yacc}/bin/yacc -P ${buildPackages.illumos.yacc}/share/lib/ccs/yaccpar")
    makeFlagsArray+=("LEX=${buildPackages.illumos.lex}/bin/lex -Y ${buildPackages.illumos.lex}/share/lib/ccs")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libavl}/lib -R${libavl}/lib -L${libidmap}/lib -R${libidmap}/lib -L${libuutil}/lib -R${libuutil}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libnvpair}/lib -R${libnvpair}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # <aclutils.h> is the only header the top lib/libsec Makefile installs, and
  # we build the amd64 subdirectory directly rather than driving the recursive
  # make. The public ACL interface itself lives in <sys/acl.h>, which the
  # headers package already ships.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libsec.so.1 "$out/lib/"
    ln -s libsec.so.1 "$out/lib/libsec.so"

    mkdir -p "$dev/include"
    cp ../common/aclutils.h "$dev/include/"

    runHook postInstall
  '';
}
