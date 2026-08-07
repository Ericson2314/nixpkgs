{
  lib,
  stdenv,
  version,
  is13,
  buildPackages,
  targetPackages,
  texinfo,
  which,
  gettext,
  autoconf269,
  gnused,
  patchelf,
  gmp,
  mpfr,
  libmpc,
  libucontext ? null,
  libxcrypt ? null,
  isSnapshot ? false,
  isl ? null,
  zlib ? null,
  gnat-bootstrap ? null,
  flex ? null,
  bison ? null,
  perl ? null,
  # True when `src` is a VCS checkout rather than a release tarball, and so
  # lacks the generated sources (gengtype-lex.cc and friends) that a tarball
  # ships pre-built.
  fromVCS ? false,
  langAda ? false,
  langGo ? false,
  langRust ? false,
  cargo,
  withoutTargetLibc ? null,
  threadsCross ? null,
  buildIsHost,
  hostIsTarget,
}:

let
  inherit (lib) optionals;
  inherit (stdenv) buildPlatform targetPlatform;
in

{
  # same for all gcc's
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  nativeBuildInputs = [
    texinfo
    which
    autoconf269
  ]
  ++ optionals (!is13) [ gettext ]
  ++ optionals (perl != null) [ perl ]
  ++ optionals (
    with stdenv.targetPlatform;
    isVc4 || isRedox || (isSnapshot || fromVCS) && flex != null
  ) [ flex ]
  ++ optionals (fromVCS && bison != null) [ bison ]
  ++ optionals langAda [ gnat-bootstrap ]
  ++ optionals langRust [ cargo ]
  # The builder relies on GNU sed (for instance, Darwin's `sed' fails with
  # "-i may not be used with stdin"), and `stdenvNative' doesn't provide it.
  ++ optionals buildPlatform.isDarwin [ gnused ];

  # For building runtime libs
  # same for all gcc's
  depsBuildTarget =
    (
      if buildIsHost then
        [
          targetPackages.stdenv.cc.bintools # newly-built gcc will be used
        ]
      else
        assert hostIsTarget;
        [
          # build != host == target
          stdenv.cc
        ]
    )
    ++ optionals targetPlatform.isLinux [ patchelf ];

  buildInputs = [
    gmp
    mpfr
    libmpc
    libxcrypt
  ]
  ++ [
    targetPackages.stdenv.cc.bintools # For linking code at run-time
  ]
  ++ optionals (isl != null) [ isl ]
  ++ optionals (zlib != null) [ zlib ]
  ++ optionals (langGo && stdenv.hostPlatform.isMusl) [ libucontext ];

  depsTargetTarget = optionals (
    !withoutTargetLibc && threadsCross != { } && threadsCross.package != null
  ) [ threadsCross.package ];
}
