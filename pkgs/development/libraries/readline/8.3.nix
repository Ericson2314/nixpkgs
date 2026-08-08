{
  lib,
  stdenv,
  fetchpatch,
  fetchurl,
  updateAutotoolsGnuConfigScriptsHook,
  ncurses,
  termcap,
  curses-library ? if stdenv.hostPlatform.isWindows then termcap else ncurses,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "readline";
  version = "8.3p${toString (builtins.length finalAttrs.upstreamPatches)}";

  src = fetchurl {
    url = "mirror://gnu/readline/readline-${finalAttrs.meta.branch}.tar.gz";
    hash = "sha256-/lODIERngozUle6NHTwDen66E4nCK8agQfYnl2+QYcw=";
  };

  outputs = [
    "out"
    "dev"
    "man"
    "doc"
    "info"
  ];

  strictDeps = true;
  propagatedBuildInputs = [ curses-library ];
  nativeBuildInputs = [ updateAutotoolsGnuConfigScriptsHook ];

  patchFlags = [ "-p0" ];

  upstreamPatches = (
    let
      patch =
        nr: sha256:
        fetchurl {
          url = "mirror://gnu/readline/readline-${finalAttrs.meta.branch}-patches/readline83-${nr}";
          inherit sha256;
        };
    in
    import ./readline-8.3-patches.nix patch
  );

  patches =
    lib.optionals (curses-library.pname == "ncurses") [
      ./link-against-ncurses.patch
    ]
    ++ [
      ./no-arch_only-8.2.patch
    ]
    ++ finalAttrs.upstreamPatches
    ++ lib.optionals stdenv.hostPlatform.isWindows [
      (fetchpatch {
        name = "0001-sigwinch.patch";
        url = "https://github.com/msys2/MINGW-packages/raw/90e7536e3b9c3af55c336d929cfcc32468b2f135/mingw-w64-readline/0001-sigwinch.patch";
        stripLen = 1;
        hash = "sha256-sFK6EJrSNl0KLWqFv5zBXaQRuiQoYIZVoZfa8BZqfKA=";
      })
      (fetchpatch {
        name = "0002-event-hook.patch";
        url = "https://github.com/msys2/MINGW-packages/raw/13d7fe6618496d509bce96e1852e943096cba6fb/mingw-w64-readline/0002-event-hook.patch";
        stripLen = 1;
        hash = "sha256-KXI85yKedS/eQ3W0a9rhG9zzN/IQT58qhPdWC2kU0Kw=";
      })
      (fetchpatch {
        name = "0003-no-winsize.patch";
        url = "https://github.com/msys2/MINGW-packages/raw/13d7fe6618496d509bce96e1852e943096cba6fb/mingw-w64-readline/0003-no-winsize.patch";
        stripLen = 1;
        hash = "sha256-+z2ak32RnDIlGbz1RwQAf4r9Scn/C3lNyEpFB5rQ5s8=";
      })
      (fetchpatch {
        name = "0004-locale.patch";
        url = "https://github.com/msys2/MINGW-packages/raw/f768c4b74708bb397a77e3374cc1e9e6ef647f20/mingw-w64-readline/0004-locale.patch";
        stripLen = 1;
        hash = "sha256-dk4343KP4EWXdRRCs8GRQlBgJFgu1rd79RfjwFD/nJc=";
      })
    ];

  # Make mingw-w64 provide a dummy alarm() function
  #
  # Method borrowed from
  # https://github.com/msys2/MINGW-packages/commit/35830ab27e5ed35c2a8d486961ab607109f5af50
  env = lib.optionalAttrs stdenv.hostPlatform.isMinGW {
    CFLAGS = toString [
      "-D__USE_MINGW_ALARM"
      "-D_POSIX"
    ];
  };

  # This install error is caused by a very old libtool. We can't autoreconfHook this package,
  # so this is the best we've got!
  postInstall = lib.optionalString stdenv.hostPlatform.isOpenBSD ''
    ln -s $out/lib/libhistory.so* $out/lib/libhistory.so
    ln -s $out/lib/libreadline.so* $out/lib/libreadline.so
  '';

  meta = {
    description = "Library for interactive line editing";

    longDescription = ''
      The GNU Readline library provides a set of functions for use by
      applications that allow users to edit command lines as they are
      typed in.  Both Emacs and vi editing modes are available.  The
      Readline library includes additional functions to maintain a
      list of previously-entered command lines, to recall and perhaps
      reedit those lines, and perform csh-like history expansion on
      previous commands.

      The history facilities are also placed into a separate library,
      the History library, as part of the build process.  The History
      library may be used without Readline in applications which
      desire its capabilities.
    '';

    homepage = "https://savannah.gnu.org/projects/readline/";

    license = lib.licenses.gpl3Plus;

    maintainers = [ ];

    platforms = lib.platforms.unix ++ lib.platforms.windows;
    branch = "8.3";
  };
}
# This has to merge in a whole *attribute* rather than read
# `postPatch = lib.optionalString cond "...";` inside the set above. An
# empty string is still a value: it would set `postPatch=""` in the
# derivation's environment on every platform, where before there was no
# `postPatch` at all, and that moves native readline's store path -- and with
# it guile, grub2 and everything else downstream. `lib.optionalAttrs` leaves
# the attribute genuinely absent off illumos, so no other platform rebuilds.
#
# TODO on staging, fold this back into the attribute set above as a plain
# `postPatch = lib.optionalString stdenv.hostPlatform.isIllumos "...";`. The
# mass rebuild is only a problem outside staging.
//
  lib.optionalAttrs stdenv.hostPlatform.isIllumos {
    # `support/shobj-conf`'s `solaris2*-*gcc*` branch picks its link flags by
    # running `gcc -print-prog-name=ld` and grepping `$ld_used -V` for "GNU".
    # Two things break that under cross compilation: the hardcoded `gcc` is not
    # on `$PATH` (only `${targetPrefix}gcc` is), and even asking `$CC` does not
    # help, because the cross gcc has no unprefixed `ld` in its exec prefix, so
    # `-print-prog-name=ld` just echoes back the bare string `ld`, which is not
    # executable here.  The probe therefore produces no output, `grep GNU`
    # fails, and the script concludes it is driving the Solaris link-editor. It
    # then emits `-Wl,-i`, which means "ignore LD_LIBRARY_PATH" to Solaris `ld`
    # but `--relocatable` to GNU `ld`, and GNU `ld` rejects `-r` with `-shared`:
    #
    #     x86_64-unknown-solaris2.11-ld.bfd: -r and -shared may not be used together
    #
    # Prefer `$LD`, which the (cross) stdenv sets to the linker actually in use,
    # falling back to the original expression for a plain native build.
    postPatch = ''
      substituteInPlace support/shobj-conf \
        --replace-fail 'ld_used=`gcc -print-prog-name=ld`' \
                       'ld_used=''${LD:-`gcc -print-prog-name=ld`}'
    '';
  })
