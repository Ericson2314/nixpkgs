{
  lib,
  symlinkJoin,
  libcMinimal,
  libpthread,
  libm,
  libresolv,
  librpcsvc,
  i18n_module,
  libutil,
  librt,
  libcrypt,
  version,
}:

symlinkJoin {
  pname = "libc-netbsd";
  inherit version;

  outputs = [
    "out"
    "dev"
    "man"
  ];

  paths =
    lib.concatMap
      (p: [
        (lib.getDev p)
        (lib.getLib p)
        (lib.getMan p)
      ])
      [
        libcMinimal
        libm
        libpthread
        libresolv
        librpcsvc
        i18n_module
        libutil
        librt
        libcrypt
      ];

  postBuild = ''
    rm -r "$out/nix-support"

    # NetBSD has no libdl: `dlopen` and friends live in libc, as on illumos and
    # Darwin. Plenty of software asks for `-ldl` anyway -- unconditionally, or
    # because a configure test for it was never taught about this platform --
    # and the link then fails outright:
    #
    #     ld: cannot find -ldl: No such file or directory
    #
    # Ship an empty archive so `-ldl` resolves and contributes nothing, which
    # is precisely what it should contribute here. `!<arch>` is the whole of a
    # valid empty archive, so this needs no target `ar`.
    printf '!<arch>\n' > "$out/lib/libdl.a"

    fixupPhase
  '';

  # NetBSD's threads are POSIX threads — `libpthread` is joined in above.
  #
  # See the comment on `threadModel` in
  # pkgs/development/compilers/gcc/ng/common/libgcc/default.nix for further
  # details.
  passthru.threadModel = "posix";

  meta.platforms = lib.platforms.netbsd;
}
