{
  lib,
  stdenv,
  buildPackages,
  fetchurl,
  updateAutotoolsGnuConfigScriptsHook,
  bison,
  util-linuxMinimal,
  coreutils,
  libredirect,
  glibcLocales,
  gnused,

  interactive ? true,
  readline,
  withDocs ? null,
  forFHSEnv ? false,

  pkgsStatic,
}:

let
  upstreamPatches = import ./bash-5.3-patches.nix (
    nr: sha256:
    fetchurl {
      url = "mirror://gnu/bash/bash-5.3-patches/bash53-${nr}";
      inherit sha256;
    }
  );
in
lib.warnIf (withDocs != null)
  ''
    bash: `.override { withDocs = true; }` is deprecated, the docs are always included.
  ''
  stdenv.mkDerivation
  (fa: {
    pname = "bash${lib.optionalString interactive "-interactive"}";
    version = "5.3${fa.patch_suffix}";
    patch_suffix = "p${toString (builtins.length upstreamPatches)}";

    src = fetchurl {
      url = "mirror://gnu/bash/bash-${lib.removeSuffix fa.patch_suffix fa.version}.tar.gz";
      hash = "sha256-DVzYaWX4aaJs9k9Lcb57lvkKO6iz104n6OnZ1VUPMbo=";
    };

    hardeningDisable = [
      "format"
    ]
    # bionic libc is super weird and has issues with fortify outside of its own libc, check this comment:
    # https://github.com/NixOS/nixpkgs/pull/192630#discussion_r978985593
    # or you can check libc/include/sys/cdefs.h in bionic source code
    ++ lib.optionals (stdenv.hostPlatform.libc == "bionic") [ "fortify" ];

    outputs = [
      "out"
      "dev"
      "man"
      "doc"
      "info"
    ];

    separateDebugInfo = true;

    env = {
      NIX_CFLAGS_COMPILE = ''
        -DSYS_BASHRC="/etc/bashrc"
        -DSYS_BASH_LOGOUT="/etc/bash_logout"
      ''
      + lib.optionalString (!forFHSEnv) ''
        -DDEFAULT_PATH_VALUE="/no-such-path"
        -DSTANDARD_UTILS_PATH="/no-such-path"
        -DDEFAULT_LOADABLE_BUILTINS_PATH="${placeholder "out"}/lib/bash:."
      ''
      + ''
        -DNON_INTERACTIVE_LOGIN_SHELLS
        -DSSH_SOURCE_BASHRC
      ''
      # Bash's configure script assumes that CC and CC_FOR_BUILD have the
      # same default -std=... flags. But at this moment, for cross llvm and FreeBSD, we
      # have CC_FOR_BUILD that defaults to c23, and a CC that default to
      # something older, perhaps c17. This breaks the build because of
      # bash's faulty assumptions.
      #
      # To fix, we simply force the standard to be the higher for CC to
      # match CC_FOR_BUILD.
      #
      # Once FreeBSD and other contexts are built with a newer version of clang,
      # this hack should be removed.
      + lib.optionalString stdenv.cc.isClang ''
        -std=c23
      '';
    }
    # The exact same asymmetry appears when cross-compiling to illumos, just
    # with two GCCs instead of clang: the cross toolchain is GCC 14 (default
    # `-std=gnu17`, so `bool` is not a keyword and `configure`'s "for bool,
    # true, false" check answers *no*, leaving `HAVE_C_BOOL` undefined), while
    # `CC_FOR_BUILD` is the native GCC 15 (default `-std=gnu23`). The build
    # tools (`mkbuiltins`, `mksignames`, ...) are compiled by `CC_FOR_BUILD`
    # but include the *host's* `config.h`, so they reach `bashansi.h`'s
    # fallback `typedef unsigned char bool;`, which GCC 15 rejects with
    # "'bool' cannot be defined via 'typedef'".
    #
    # Here we close the gap from the other side and pin `CC_FOR_BUILD` to the
    # language level the host compiler actually reported on, rather than
    # raising CC to `-std=c23` as the clang branch above does. That keeps the
    # bulk of the tree compiling exactly as `configure` probed it.
    // lib.optionalAttrs (stdenv.hostPlatform.isIllumos && !stdenv.cc.isClang) {
      NIX_CFLAGS_COMPILE_FOR_BUILD = "-std=gnu17";
    };

    patchFlags = [ "-p0" ];

    patches =
      upstreamPatches
      ++ [
        # Enable PGRP_PIPE independently of the kernel of the build machine.
        # This doesn't seem to be upstreamed despite such a mention of in https://github.com/NixOS/nixpkgs/pull/77196,
        # which originally introduced the patch
        # Some related discussion can be found in
        # https://lists.gnu.org/archive/html/bug-bash/2015-05/msg00071.html
        ./pgrp-pipe-5.patch
      ]
      # Both of these are latent upstream bugs that only illumos has tripped
      # over so far; they are kept off every other platform's store path until
      # they are upstreamed.
      ++ lib.optionals stdenv.hostPlatform.isIllumos [
        # Only platforms without `getpeername` reach the broken `!HAVE_NETWORK`
        # stub in `lib/sh/netopen.c`. illumos no longer does now that
        # `libsocket` is packaged, but keep the fix: the stub is still wrong,
        # and `HAVE_NETWORK` is one failed `configure` probe away from
        # vanishing again.
        ./netopen-no-network-includes.patch
        # `support/Makefile.in` links the build-time `man2html` with
        # `CC_FOR_BUILD` but passes it the host's `$(LIBS)`. illumos is where
        # that first bites, because `LIBS` there contains `-lsocket -lnsl`.
        ./support-libs-for-build.patch
      ];

    configureFlags = [
      # At least on Linux bash memory allocator has pathological performance
      # in scenarios involving use of larger memory:
      #   https://lists.gnu.org/archive/html/bug-bash/2023-08/msg00052.html
      # Various distributions default to system allocator. Let's nixpkgs
      # do the same.
      "--without-bash-malloc"
      (if interactive then "--with-installed-readline" else "--disable-readline")
    ]
    ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "bash_cv_job_control_missing=nomissing"
      "bash_cv_sys_named_pipes=nomissing"
      "bash_cv_getcwd_malloc=yes"
      # This check cannot be performed when cross compiling. The "yes"
      # default is fine for static linking on Linux (weak symbols?) but
      # not with BSDs, when it does clash with the regular `getenv`.
      "bash_cv_getenv_redef=${
        lib.boolToYesNo (!(with stdenv.hostPlatform; isStatic && (isOpenBSD || isFreeBSD)))
      }"
    ]
    ++ lib.optionals stdenv.hostPlatform.isCygwin [
      "bash_cv_dev_stdin=present"
      "bash_cv_dev_fd=standard"
      "gt_cv_func_printf_posix=yes"
    ]
    ++ lib.optionals (stdenv.hostPlatform.libc == "musl") [
      "--disable-nls"
    ]
    ++ lib.optionals stdenv.hostPlatform.isFreeBSD [
      # /dev/fd is optional on FreeBSD. we need it to work when built on a system
      # with it and transferred to a system without it! This includes linux cross.
      "bash_cv_dev_fd=absent"
    ];

    strictDeps = true;
    # Note: Bison is needed because the patches above modify parse.y.
    depsBuildBuild = [ buildPackages.stdenv.cc ];
    nativeBuildInputs = [
      updateAutotoolsGnuConfigScriptsHook
      bison
    ]
    ++ lib.optionals stdenv.hostPlatform.isDarwin [ stdenv.cc.bintools ];

    buildInputs = lib.optionals interactive [ readline ];

    enableParallelBuilding = true;

    doCheck = false; # Can't be enabled by default due to dependency cycle, use passthru.tests.withChecks instead

    postInstall = ''
      ln -s bash${stdenv.hostPlatform.extensions.executable} "$out/bin/sh"
      rm -f $out/lib/bash/Makefile.inc
    '';

    postFixup =
      if interactive then
        ''
          substituteInPlace "$out/bin/bashbug" \
            --replace '#!/bin/sh' "#!$out/bin/bash"
        ''
      # most space is taken by locale data
      else
        ''
          rm -rf "$out/share" "$out/bin/bashbug"
        '';

    passthru = {
      shellPath = "/bin/bash";
      tests.static = pkgsStatic.bash;
      tests.withChecks = fa.finalPackage.overrideAttrs (attrs: {
        doCheck = true;

        nativeCheckInputs = attrs.nativeCheckInputs or [ ] ++ [
          util-linuxMinimal
          libredirect.hook
          glibcLocales
          gnused
        ];

        meta = attrs.meta // {
          # Ignore Darwin for now, because the tests fail in many more ways than on Linux
          broken = attrs.meta.broken or false || stdenv.buildPlatform.isDarwin;
        };

        patches = attrs.patches or [ ] ++ [
          # See commit comment, also submitted upstream: https://lists.gnu.org/archive/html/bug-bash/2025-10/msg00054.html
          ./fail-tests.patch
          # See commit comment, also submitted upstream: https://lists.gnu.org/archive/html/bug-bash/2025-10/msg00055.html
          ./failed-tests-output.patch
          # The run-builtins test _almost_ succeeds, only has a bit of PATH trouble
          # and some odd terminal column mismatch
          ./fix-builtins-tests.patch
          # The run-invocation test _almost_ succeeds, only has a bit of PATH trouble
          ./fix-invocation-tests.patch
        ];

        preCheck = attrs.preCheck or "" + ''
          # Allows looking at actual outputs for failed tests
          export BASH_TSTOUT_KEEPDIR=$(mktemp -d)
          export HOME=$(mktemp -d)
          export NIX_REDIRECTS=${
            lib.concatMapAttrsStringSep ":" (name: value: "${name}=${value}") {
              "/bin/echo" = lib.getExe' coreutils "echo";
              "/bin/cat" = lib.getExe' coreutils "cat";
              "/bin/rm" = lib.getExe' coreutils "rm";
              "/usr" = "$(mktemp -d)";
            }
          }

          disabled_checks=(
            # Unsets PATH and breaks, not clear
            run-execscript

            # Fails on ZFS & needs a ja_JP.SJIS locale, which glibcLocales doesn't have
            run-intl

            # These error with "echo: write error: Broken pipe"
            run-histexpand
            run-lastpipe
            run-comsub
            run-comsub2

            # For some reason has an extra 'declare -x version="5.2p37"'
            run-nameref

            # These print some extra 'trap -- ''' SIGPIPE'
            run-trap
            run-varenv

            # These rely on /dev/tty
            run-read
            run-test
            run-vredir

            # Might also be related to not having a tty: "Inappropriate ioctl for device"
            run-history

            # Can be enabled in 5.4
            run-printf

            # This is probably fixable without too much trouble, but just not having a hardcoded PATH in type5.sub doesn't cut it
            # 142,143c142,147
            # < type5.sub: line 23: mkdir: command not found
            # < type5.sub: line 24: cd: /build/type-23722: No such file or directory
            # ---
            # > cat is /bin/cat
            # > cat is aliased to `echo cat'
            # > /bin/cat
            # > break is a shell builtin
            # > break is a special shell builtin
            # > ./e
            run-type
          )
          for check in "''${disabled_checks[@]}"; do
            # Exit before running the test script
            sed -i "1iecho 'Skipping test $check' >&2 && exit 0" "tests/$check"
          done
        '';
      });
    };

    meta = {
      homepage = "https://www.gnu.org/software/bash/";
      description =
        "GNU Bourne-Again Shell, the de facto standard shell on Linux"
        + lib.optionalString interactive " (for interactive use)";
      longDescription = ''
        Bash is the shell, or command language interpreter, that will
        appear in the GNU operating system.  Bash is an sh-compatible
        shell that incorporates useful features from the Korn shell
        (ksh) and C shell (csh).  It is intended to conform to the IEEE
        POSIX P1003.2/ISO 9945.2 Shell and Tools standard.  It offers
        functional improvements over sh for both programming and
        interactive use.  In addition, most sh scripts can be run by
        Bash without modification.
      '';
      license = lib.licenses.gpl3Plus;
      platforms = lib.platforms.all;
      # https://github.com/NixOS/nixpkgs/issues/333338
      badPlatforms = [ lib.systems.inspect.patterns.isMinGW ];
      maintainers = with lib.maintainers; [ infinisil ];
      teams = [ lib.teams.security-review ];
      mainProgram = "bash";
      identifiers.cpeParts =
        let
          versionSplit = lib.split "p" fa.version;
        in
        {
          vendor = "gnu";
          product = "bash";
          version = lib.elemAt versionSplit 0;
          update = lib.elemAt versionSplit 2;
        };
    };
  })
