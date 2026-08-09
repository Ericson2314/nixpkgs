{
  lib,
  stdenv,
  mkMesonLibrary,

  boost,
  brotli,
  libarchive,
  libblake3,
  libcpuid,
  libsodium,
  nlohmann_json,
  openssl,
  zstd,

  # Configuration Options

  version,
}:

mkMesonLibrary (finalAttrs: {
  pname = "nix-util";
  inherit version;

  workDir = ./.;

  buildInputs = [
    brotli
  ]
  ++ lib.optional (lib.versionAtLeast version "2.27") libblake3
  ++ lib.optional (lib.versionAtLeast version "2.35pre") zstd
  ++ [
    libsodium
    openssl
  ]
  ++ lib.optional stdenv.hostPlatform.isx86_64 libcpuid;

  propagatedBuildInputs = [
    boost
    libarchive
    nlohmann_json
  ];

  mesonFlags = [
    (lib.mesonEnable "cpuid" stdenv.hostPlatform.isx86_64)
  ];

  # terminal.cc reaches for `struct winsize` and TIOCGWINSZ having included
  # only <sys/ioctl.h>. That suffices on Linux and the BSDs, but illumos
  # declares both in <sys/termios.h>, reached via <termios.h>:
  #
  #   terminal.cc:171:20: error: aggregate 'nix::updateWindowSize()::winsize
  #   ws' has incomplete type and cannot be defined
  #   terminal.cc:172:18: error: 'TIOCGWINSZ' was not declared in this scope
  #
  # Adding the include upstream is the real fix; force it here rather than
  # patch, because this component shares one source tree with the others.
  # (-lsocket/-lnsl come from the illumosSocketLibs layer in components.nix.)
  env = lib.optionalAttrs stdenv.hostPlatform.isSunOS {
    NIX_CFLAGS_COMPILE = "-include termios.h";
  };

  meta = {
    platforms = lib.platforms.unix ++ lib.platforms.windows;
  };

})
