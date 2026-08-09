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
# grammar) and `acl_lex.l`. Upstream builds them with illumos' own yacc/lex out
# of `usr/src/tools`, which have no build-host build here; bison's `-y` POSIX
# mode and flex are drop-in enough for this grammar.
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
    buildPackages.bison
    buildPackages.flex
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

  # `Makefile.master` points YACC and LEX at `$(ONBLD_TOOLS)/bin/$(MACH)/`,
  # illumos' own (AT&T-derived) yacc and lex, built from `usr/src/cmd/sgs`.
  # Neither has a build-host build here, so use bison in POSIX/yacc mode and
  # flex. The `-P`/`-Y` arguments in the upstream definitions name the illumos
  # skeleton files and go away with them.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. libidmap's own
  # dependencies (libavl, libuutil, libnsl, libnvpair, and libnsl's libmd and
  # libmp) all have to be on the path too.
  #
  # `YACC` goes through `makeFlagsArray` rather than `makeFlags` because it
  # contains a space, and `makeFlags` entries are word-split.
  preBuild = ''
    makeFlagsArray+=("YACC=bison -y")
    makeFlagsArray+=("LEX=flex")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libavl}/lib -L${libidmap}/lib -L${libuutil}/lib -L${libnsl}/lib -L${libnvpair}/lib -L${libmd}/lib -L${libmp}/lib \$(LDLIBS)")
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
