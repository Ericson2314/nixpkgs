{ stdenv, lib, stdenvNoCC
, pkgsBuildBuild, pkgsBuildHost, pkgsBuildTarget, pkgsHostHost, pkgsTargetTarget
, buildPackages, splicePackages, newScope
, bsdSetupHook, makeSetupHook
, fetchgit, fetchurl, coreutils, groff, mandoc, byacc, flex, which
, zlib, expat, libbsd, libmd
, runCommand, writeScript, writeText, runtimeShell, symlinkJoin
}:

let
  inherit (buildPackages.buildPackages) rsync;

  version = "13.0.0";

  # `BuildPackages.fetchgit` avoids some probably splicing-caused infinite
  # recursion.
  freebsdSrc = buildPackages.fetchgit {
    url = "https://git.FreeBSD.org/src.git";
    rev = "release/${version}";
    sha256 = "1r5v9i3ajgqmkrvgp4pdz98g2q6dagzjb2hxpbwcwndisvz28rnr";
  };

  otherSplices = {
    selfBuildBuild = pkgsBuildBuild.freebsd;
    selfBuildHost = pkgsBuildHost.freebsd;
    selfBuildTarget = pkgsBuildTarget.freebsd;
    selfHostHost = pkgsHostHost.freebsd;
    selfTargetTarget = pkgsTargetTarget.freebsd or {}; # might be missing
  };

  mkBsdArch = stdenv':  {
    x86_64 = "amd64";
    aarch64 = "arm64";
    i486 = "i386";
    i586 = "i386";
    i686 = "i386";
  }.${stdenv'.hostPlatform.parsed.cpu.name}
    or stdenv'.hostPlatform.parsed.cpu.name;

in lib.makeScopeWithSplicing
  splicePackages
  newScope
  otherSplices
  (_: {})
  (_: {})
  (self: let
    inherit (self) mkDerivation;
  in {
  inherit freebsdSrc;

  # Why do we have splicing and yet do `nativeBuildInputs = with self; ...`?
  # See note in ../netbsd/default.nix.

  compatIfNeeded = lib.optional (!stdenvNoCC.hostPlatform.isFreeBSD) self.compat;

  mkDerivation = lib.makeOverridable (attrs: let
    stdenv' = if attrs.noCC or false then stdenvNoCC else stdenv;
  in stdenv'.mkDerivation (rec {
    pname = "${attrs.pname or (baseNameOf attrs.path)}-freebsd";
    inherit version;
    src = runCommand "${pname}-filtered-src" {
      nativeBuildInputs = [ rsync ];
    } ''
      for p in ${lib.concatStringsSep " " ([ attrs.path ] ++ attrs.extraPaths or [])}; do
        set -x
        path="$out/$p"
        mkdir -p "$(dirname "$path")"
        src_path="${freebsdSrc}/$p"
        if [[ -d "$src_path" ]]; then src_path+=/; fi
        rsync --chmod="+w" -r "$src_path" "$path"
        set +x
      done
    '';

    extraPaths = [ ];

    nativeBuildInputs = with buildPackages.freebsd; [
      bsdSetupHook
      makeMinimal
      install tsort lorder mandoc groff statHook
    ];
    buildInputs = with self; compatIfNeeded;

    HOST_SH = stdenv'.shell;

    makeFlags = lib.optional (!stdenv.hostPlatform.isFreeBSD) "MK_WERROR=no";

    MACHINE_ARCH = {
      i486 = "i386";
      i586 = "i386";
      i686 = "i386";
    }.${stdenv'.hostPlatform.parsed.cpu.name}
      or stdenv'.hostPlatform.parsed.cpu.name;

    MACHINE = mkBsdArch stdenv';

    MACHINE_CPUARCH = MACHINE_ARCH;

    BSD_PATH = attrs.path or null;

    strictDeps = true;

    meta = with lib; {
      maintainers = with maintainers; [ ericson2314 ];
      platforms = platforms.unix;
      license = licenses.bsd2;
    };
  } // lib.optionalAttrs stdenv'.hasCC {
    # TODO should CC wrapper set this?
    CPP = "${stdenv'.cc.targetPrefix}cpp";
  } // lib.optionalAttrs stdenv'.isDarwin {
    MKRELRO = "no";
  } // lib.optionalAttrs (stdenv'.cc.isClang or false) {
    HAVE_LLVM = lib.versions.major (lib.getVersion stdenv'.cc.cc);
  } // lib.optionalAttrs (stdenv'.cc.isGNU or false) {
    HAVE_GCC = lib.versions.major (lib.getVersion stdenv'.cc.cc);
  } // lib.optionalAttrs (stdenv'.isx86_32) {
    USE_SSP = "no";
  } // lib.optionalAttrs (attrs.headersOnly or false) {
    installPhase = "includesPhase";
    dontBuild = true;
  } // attrs));

  ##
  ## START BOOTSTRAPPING
  ##
  makeMinimal = mkDerivation rec {
    inherit (self.make) path;

    buildInputs = with self; [];
    nativeBuildInputs = with buildPackages.netbsd; [ bsdSetupHook ];

    skipIncludesPhase = true;

    makeFlags = [];

    postPatch = ''
      patchShebangs configure
      ${self.make.postPatch}
    '';

    buildPhase = ''
      runHook preBuild

      sh ./make-bootstrap.sh

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -D bmake $out/bin/bmake
      ln -s $out/bin/bmake $out/bin/make
      mkdir -p $out/share
      cp -r $BSDSRCDIR/share/mk $out/share/mk
      find "$out/share/mk" -type f -print0 |
        while IFS= read -r -d "" f; do
          substituteInPlace "$f" --replace 'usr/' ""
        done

      runHook postInstall
    '';

    postInstall = lib.optionalString (!stdenv.hostPlatform.isFreeBSD) ''
      boot_mk=$BSDSRCDIR/tools/build/mk
      cp $boot_mk/Makefile.boot* $out/share/mk
      replaced_mk=$out/share/mk.orig
      mkdir $replaced_mk
      mv $out/share/mk/bsd.{lib,prog}.mk $replaced_mk
      for m in bsd.{lib,prog}.mk; do
        cp $boot_mk/$m $out/share/mk
        substituteInPlace $out/share/mk/$m --replace '../../../share/mk' '../mk.orig'
      done
    '';

    extraPaths = with self; make.extraPaths;
  };

  # Wrap NetBSD's install
  boot-install = buildPackages.writeScriptBin "boot-install" ''
    #!${stdenv.shell}

    set -eu

    args=()
    declare -i path_args=0

    while (( $# )); do
      if (( $# == 1 )); then
        if (( $path_args > 1)) || [[ "$1" = */ ]]; then
          mkdir -p "$1"
        else
          mkdir -p "$(dirname "$1")"
        fi
      fi
      case $1 in
        -C) ;;
        strip) ;;
        -o | -g) shift ;;
        -m)
          # handle next arg so not counted as path arg
          args+=("$1" "$2")
          shift
          ;;
        -*) args+=("$1") ;;
        *)
          path_args+=1
          args+=("$1")
          ;;
      esac
      shift
    done

    ${buildPackages.netbsd.install}/bin/xinstall "''${args[@]}"
  '';

  compat = mkDerivation rec {
    pname = "compat";
    path = "tools/build";
    extraPaths = [
      "lib/libc/db"
      "lib/libc/stdlib" # getopt
      "lib/libc/gen" # getcap
      "lib/libc/locale" # rpmatch
    ] ++ lib.optionals stdenv.hostPlatform.isLinux [
      "lib/libc/string" # strlcpy
      "lib/libutil"
    ] ++ [
      "contrib/libc-pwcache"
      "contrib/libc-vis"
      "sys/libkern"
      "sys/kern/subr_capability.c"

	  # Take only individual headers, or else we will clobber native libc, etc.

      "sys/rpc/types.h"

      # Listed in Makekfile as INC
      "include/mpool.h"
      "include/ndbm.h"
      "include/err.h"
      "include/stringlist.h"
      "include/a.out.h"
      "include/nlist.h"
      "include/db.h"
      "include/getopt.h"
      "include/nl_types.h"
      "include/elf.h"

      # Listed in Makekfile as SYSINC

      "sys/sys/capsicum.h"
      "sys/sys/caprights.h"
      "sys/sys/imgact_aout.h"
      "sys/sys/nlist_aout.h"
      "sys/sys/nv.h"
      "sys/sys/dnv.h"
      "sys/sys/cnv.h"

      "sys/sys/elf32.h"
      "sys/sys/elf64.h"
      "sys/sys/elf_common.h"
      "sys/sys/elf_generic.h"
      "sys/${mkBsdArch stdenv}/include"
    ] ++ lib.optionals stdenv.hostPlatform.isx86 [
      "sys/x86/include"
    ] ++ [

	  "sys/sys/queue.h"
	  "sys/sys/md5.h"
	  "sys/sys/sbuf.h"
	  "sys/sys/tree.h"
	  "sys/sys/font.h"
	  "sys/sys/consio.h"
	  "sys/sys/fnv_hash.h"

      "sys/crypto/chacha20/_chacha.h"
      "sys/crypto/chacha20/chacha.h"
      # included too, despite ".c"
      "sys/crypto/chacha20/chacha.c"

      "sys/fs"
      "sys/ufs"
      "sys/sys/disk"

      "lib/libcapsicum"
      "lib/libcasper"
    ];

    patches = [
      ./compat-install-dirs.patch
      ./compat-fix-typedefs-locations.patch
    ];

    preBuild = ''
      NIX_CFLAGS_COMPILE+=' -I../../include -I../../sys'

      cp ../../sys/${mkBsdArch stdenv}/include/elf.h ../../sys/sys
      cp ../../sys/${mkBsdArch stdenv}/include/elf.h ../../sys/sys/${mkBsdArch stdenv}
    '' + lib.optionalString stdenv.hostPlatform.isx86 ''
      cp ../../sys/x86/include/elf.h ../../sys/x86
    '';

    setupHooks = [
      ../../../build-support/setup-hooks/role.bash
      ./compat-setup-hook.sh
    ];

    nativeBuildInputs = with buildPackages.freebsd; [
      bsdSetupHook
      makeMinimal
      boot-install

      which
    ];
    buildInputs = [ expat zlib ];

    makeFlags = [
      "MK_WERROR=no"
      "HOST_INCLUDE_ROOT=${lib.getDev stdenv.cc.libc}/include"
      "SRCTOP=../.."
      "INSTALL=boot-install"
    ];

    preIncludes = ''
      mkdir -p $out/include
      cp --no-preserve=mode -r cross-build/include/common/* $out/include
    '' + lib.optionalString stdenv.hostPlatform.isLinux ''
      cp --no-preserve=mode -r cross-build/include/linux/* $out/include
    '' + lib.optionalString stdenv.hostPlatform.isDarwin ''
      cp --no-preserve=mode -r cross-build/include/darwin/* $out/include
    '';
  };

  libnetbsd = mkDerivation {
    path = "lib/libnetbsd";
    nativeBuildInputs = with buildPackages.freebsd; [
      bsdSetupHook
      makeMinimal mandoc groff
      (if stdenv.hostPlatform == stdenv.buildPlatform
       then boot-install
       else install)
    ];
    patches = lib.optionals (!stdenv.hostPlatform.isFreeBSD) [
      ./libnetbsd-do-install.patch
      #./libnetbsd-define-__va_list.patch
    ];
    makeFlags = [
      "MK_WERROR=no"
      "SRCTOP=../.."
    ] ++ lib.optional (stdenv.hostPlatform == stdenv.buildPlatform) "INSTALL=boot-install";
    buildInputs = with self; compatIfNeeded;
  };

  # HACK: to ensure parent directories exist. This emulates GNU
  # install’s -D option. No alternative seems to exist in BSD install.
  install = let binstall = writeScript "binstall" ''
    #!${runtimeShell}
    set -eu
    for last in "$@"; do true; done
    mkdir -p $(dirname $last)
    @out@/bin/xinstall "$@"
  ''; in mkDerivation {
    path = "usr.bin/xinstall";
    extraPaths = with self; [ mtree.path ];
    nativeBuildInputs = with buildPackages.freebsd; [
      bsdSetupHook
      makeMinimal mandoc groff
      (if stdenv.hostPlatform == stdenv.buildPlatform
       then boot-install
       else install)
    ];
    skipIncludesPhase = true;
    buildInputs = with self; compatIfNeeded ++ [ libmd libnetbsd ];
    makeFlags = [
      "MK_WERROR=no"
      "SRCTOP=../.."
      "TESTSDIR=${builtins.placeholder "test"}"
    ] ++ lib.optional (stdenv.hostPlatform == stdenv.buildPlatform) "INSTALL=boot-install";
    postInstall = ''
      install -D -m 0550 ${binstall} $out/bin/binstall
      substituteInPlace $out/bin/binstall --subst-var out
      mv $out/bin/install $out/bin/xinstall
      ln -s ./binstall $out/bin/install
    '';
    outputs = [ "out" "man" "test" ];
  };

  fts = mkDerivation {
    path = "include/fts.h";
    nativeBuildInputs = with buildPackages.freebsd; [
      bsdSetupHook
    ];
    propagatedBuildInputs = with self; compatIfNeeded;
    extraPaths = with self; [
      "include/fts.h"
      "lib/libc/gen/fts.c"
      "lib/libc/include/namespace.h"
      "lib/libc/include/un-namespace.h"
      "lib/libc/gen/fts.3"
      "lib/libc/gen/gen-private.h"
    ];
    skipIncludesPhase = true;
    buildPhase = ''
      "$CC" -c -Iinclude -Ilib/libc/include -Ilib/libc/gen lib/libc/gen/fts.c \
          -o lib/libc/gen/fts.o
      "$AR" -rsc libfts.a lib/libc/gen/fts.o
    '';
    installPhase = ''
      runHook preInstall

      install -D lib/libc/gen/fts.3 $out/share/man/man3/fts.3
      install -D include/fts.h $out/include/fts.h
      install -D lib/libc/include/namespace.h $out/include/namespace.h
      install -D lib/libc/include/un-namespace.h $out/include/un-namespace.h
      install -D libfts.a $out/lib/libfts.a

      runHook postInstall
    '';
    setupHooks = [
      ../../../build-support/setup-hooks/role.bash
      ./../netbsd/fts-setup-hook.sh
    ];
  };

  # Don't add this to nativeBuildInputs directly.  Use statHook instead.
  stat = mkDerivation {
    path = "usr.bin/stat";
    nativeBuildInputs = with buildPackages.freebsd; [
      bsdSetupHook
      makeMinimal install mandoc groff
    ];
  };

  # stat isn't in POSIX, and NetBSD stat supports a completely
  # different range of flags than GNU stat, so including it in PATH
  # breaks stdenv.  Work around that with a hook that will point
  # NetBSD's build system and NetBSD stat without including it in
  # PATH.
  statHook = makeSetupHook {
    name = "netbsd-stat-hook";
  } (writeText "netbsd-stat-hook-impl" ''
    makeFlagsArray+=(TOOL_STAT=${self.stat}/bin/stat)
  '');

  tsort = mkDerivation {
    path = "usr.bin/tsort";
    nativeBuildInputs = with buildPackages.freebsd; [
      bsdSetupHook
      makeMinimal install mandoc groff
    ];
  };

  lorder = mkDerivation rec {
    path = "usr.bin/lorder";
    noCC = true;
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out/bin" "$man/share/man"
      mv "$BSDSRCDIR/${path}/lorder.sh" "$out/bin/lorder"
      chmod +x "$out/bin/lorder"
      mv "$BSDSRCDIR/${path}/lorder.1" "$man/share/man"
      exit 0;
    '';
    nativeBuildInputs = [ bsdSetupHook ];
    buildInputs = [];
    outputs = [ "out" "man" ];
  };

  ##
  ## END BOOTSTRAPPING
  ##

  make = mkDerivation {
    path = "contrib/bmake";
    version = "9.2";
    postPatch = ''
      # make needs this to pick up our sys make files
      export NIX_CFLAGS_COMPILE+=" -D_PATH_DEFSYSPATH=\"$out/share/mk\""

    '' + lib.optionalString stdenv.isDarwin ''
      substituteInPlace $BSDSRCDIR/share/mk/bsd.sys.mk \
        --replace '-Wl,--fatal-warnings' "" \
        --replace '-Wl,--warn-shared-textrel' ""
    '';
    postInstall = ''
      make -C $BSDSRCDIR/share/mk FILESDIR=$out/share/mk install
    '';
    extraPaths = [ "share/mk" ]
      ++ lib.optional (!stdenv.hostPlatform.isFreeBSD) "tools/build/mk";
  };
  mtree = mkDerivation {
    path = "contrib/mtree";
    extraPaths = with self; [ mknod.path ];
  };

  mknod = mkDerivation {
    path = "sbin/mknod";
  };

  rpcgen = mkDerivation rec {
    path = "usr.bin/rpcgen";
    # for debugging
    # makeFlags = defaultMakeFlags ++ [ "-d x" ];
    # NIX_DEBUG = 7;
  };

  libc = mkDerivation rec {
    pname = "libc";
    path = "lib/libc";

    #src = fetchFreeBSD "" "0rmq7jlymjq3k9d9j5yr85krk2lmmgyjfwzybb02h4dfyq0wssri";
    #src = runCommand "filtered-freebsd-src-root" {} ''
    #  mkdir -p $out/lib
    #  cp --no-preserve=mode -r  \
    #    ${fetchFreeBSD "lib/libc" "1baqzyy7pa4snplg0bgh77p76sqkz9j92r36lp1k8341im4w4sas"} \
    #    "$out/lib/libc"
    # #  cp --no-preserve=mode -r  \
    # #    ${fetchFreeBSD "lib/libmd" "083bpikmlq82xqz14g29bcsm8iaiy3n9xd1v725bvb1j2yc9xg5n"} \
    # #    "$out/lib/libmd"
    #  cp --no-preserve=mode -r \
    #    ${fetchFreeBSD "lib/msun" "1bnz3vx380b6fqkd3jmfajazmsasrwmmjak7mgl3dmvhjyxsss6r"} \
    #    "$out/lib/msun"
    #  mkdir -p $out/sys
    #  cp --no-preserve=mode -r \
    #    ${fetchFreeBSD "sys/sys" "1qd3fb14z939sv46yyalpdqq3kw7rgki599aswibjc1mfxxsbsai"} \
    #    "$out/sys/sys"
    #  mkdir -p $out/contrib
    #  cp --no-preserve=mode -r \
    #    ${fetchFreeBSD "contrib/libc-pwcache" "0sydgas4dimym1sbaqp1as70a1bg83iqpllfhys51gmjzqis02na"} \
    #    "$out/contrib/libc-pwcache"
    #  cp --no-preserve=mode -r \
    #    ${fetchFreeBSD "contrib/libc-vis" "14d8jjrh4j3n51vqwf2bdvci19k8xpfdq97gyqch4cakwi1p1fn1"} \
    #    "$out/contrib/libc-vis"
    #'';

    postUnpack = ''
      sourceRoot+="/lib/libc";
    '';

    preConfigure = ''
      export SRCTOP=$(readlink -e ../..)
      touch src.opts.mk
    '';

    MK_SYMVER = "yes";
    MK_SSP = "yes";
    MK_NLS = "yes";
    MK_ICONV = "no"; # TODO make srctop
    MK_NS_CACHING = "yes";
    MK_INET6_SUPPORT = "yes";
    MK_HESIOD = "yes";
    MK_NIS = "yes";
    MK_HYPERV = "yes";
    MK_FP_LIBC = "yes";
  };

})
