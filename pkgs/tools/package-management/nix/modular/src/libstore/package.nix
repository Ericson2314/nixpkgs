{
  lib,
  stdenv,
  mkMesonLibrary,

  unixtools,
  freebsd,

  nix-util,
  boost,
  curl,
  cmake,
  aws-c-common,
  aws-sdk-cpp,
  aws-crt-cpp,
  libseccomp,
  nlohmann_json,
  sqlite,

  busybox-sandbox-shell ? null,
  pkgsStatic,

  # Configuration Options

  version,

  embeddedSandboxShell ? stdenv.hostPlatform.isStatic,

  withSandboxShell ?
    stdenv.hostPlatform.isLinux
    || (lib.versionAtLeast version "2.35pre" && stdenv.hostPlatform.isFreeBSD),
  sandboxShell ?
    if stdenv.hostPlatform.isLinux then
      "${busybox-sandbox-shell}/bin/busybox"
    else if stdenv.hostPlatform.isFreeBSD then
      "${pkgsStatic.bash}/bin/bash"
    else
      null,

  withAWS ?
    # Default is this way because there have been issues building this dependency
    # TODO: aws-crt-cpp is broken on cygwin, find a good way to check that here
    # Ditto illumos: aws-c-common itself builds, but aws-c-io has no event loop
    # backend for it -- it offers epoll, kqueue and IOCP only, and stops with
    # "Event Loop is not setup on the platform." illumos would want an event
    # ports (port_create) backend, which is an upstream port rather than a
    # packaging fix. Note this probe asks about aws-c-common, which is not the
    # dependency that actually fails.
    lib.meta.availableOn stdenv.hostPlatform aws-c-common
    && !stdenv.hostPlatform.isCygwin
    && !stdenv.hostPlatform.isSunOS,
}:

mkMesonLibrary (finalAttrs: {
  pname = "nix-store";
  inherit version;

  workDir = ./.;

  nativeBuildInputs =
    lib.optional embeddedSandboxShell unixtools.hexdump
    ++ lib.optional (withAWS && lib.versionAtLeast version "2.34pre") cmake;

  buildInputs = [
    boost
    curl
    sqlite
  ]
  ++ lib.optional (
    lib.versionAtLeast version "2.35pre" && stdenv.hostPlatform.isFreeBSD
  ) freebsd.libjail
  ++ lib.optional stdenv.hostPlatform.isLinux libseccomp
  # There have been issues building these dependencies
  ++
    lib.optional withAWS
      # Nix >=2.33 doesn't depend on aws-sdk-cpp and only requires aws-crt-cpp for authenticated s3:// requests.
      (if lib.versionAtLeast (lib.versions.majorMinor version) "2.33" then aws-crt-cpp else aws-sdk-cpp);

  propagatedBuildInputs = [
    nix-util
    nlohmann_json
  ];

  mesonFlags = [
    (lib.mesonEnable "seccomp-sandboxing" stdenv.hostPlatform.isLinux)
    (lib.mesonBool "embedded-sandbox-shell" embeddedSandboxShell)
  ]
  ++ lib.optional (lib.versionAtLeast (lib.versions.majorMinor version) "2.33") (
    lib.mesonEnable "s3-aws-auth" withAWS
  )
  ++ lib.optionals withSandboxShell [
    (lib.mesonOption "sandbox-shell" sandboxShell)
  ];

  # cfmakeraw(3) is a BSD extension that glibc and the BSDs carry but POSIX
  # never standardised, and illumos does not have it at all. The build sandbox's
  # pty setup calls it:
  #
  #   unix/build/derivation-builder.cc:980:5: error: 'cfmakeraw' was not
  #   declared in this scope
  #
  # Supply the standard definition. Force-included rather than patched in,
  # because the nix components share a single source tree.
  #
  # (-lsocket/-lnsl come from the illumosSocketLibs layer in components.nix.)
  env = lib.optionalAttrs stdenv.hostPlatform.isSunOS {
    NIX_CFLAGS_COMPILE = "-include ${./illumos-cfmakeraw.h}";
  };

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
