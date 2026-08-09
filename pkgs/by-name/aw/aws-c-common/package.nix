{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  nix,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "aws-c-common";
  # nixpkgs-update: no auto update
  version = "0.12.4";

  src = fetchFromGitHub {
    owner = "awslabs";
    repo = "aws-c-common";
    rev = "v${finalAttrs.version}";
    hash = "sha256-hKCIPZlLPyH7D3Derk2onyqTzWGUtCx+f2+EKtAKlwA=";
  };

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DBUILD_SHARED_LIBS=ON"
  ]
  ++ lib.optionals stdenv.hostPlatform.isRiscV [
    "-DCMAKE_C_FLAGS=-fasynchronous-unwind-tables"
  ];

  # illumos declares flock(3C) in <sys/file.h> as
  #
  #   #if !defined(_STRICT_SYMBOLS)
  #   extern int flock(int, int);
  #
  # and <sys/feature_tests.h> sets _STRICT_SYMBOLS whenever _STRICT_STDC or
  # __XOPEN_OR_POSIX is in effect without __EXTENSIONS__. The LOCK_* constants
  # right next to it are *not* guarded, so source/posix/cross_process_lock.c
  # compiles all the way to the call site and only the declaration is missing:
  #
  #   cross_process_lock.c:108:9: error: implicit declaration of function
  #   'flock'; did you mean 'clock'?
  #
  # __EXTENSIONS__ is illumos' documented opt-in for exactly this.
  env = lib.optionalAttrs stdenv.hostPlatform.isSunOS {
    NIX_CFLAGS_COMPILE = "-D__EXTENSIONS__";
  };

  # aws-c-common misuses cmake modules, so we need
  # to manually add a MODULE_PATH to its consumers
  setupHook = ./setup-hook.sh;

  # Prevent the execution of tests known to be flaky.
  preCheck =
    let
      ignoreTests = [
        "promise_test_multiple_waiters"
        # Flaky test https://github.com/NixOS/nixpkgs/issues/443233
        "test_memory_usage_maxrss"
      ];
    in
    ''
      cat <<EOW >CTestCustom.cmake
      SET(CTEST_CUSTOM_TESTS_IGNORE ${toString ignoreTests})
      EOW
    '';

  doCheck = true;

  passthru.tests = {
    inherit nix;
  };

  meta = {
    description = "AWS SDK for C common core";
    homepage = "https://github.com/awslabs/aws-c-common";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
    # https://github.com/awslabs/aws-c-common/issues/1175
    badPlatforms = lib.platforms.bigEndian;
    maintainers = with lib.maintainers; [
      r-burns
    ];
  };
})
