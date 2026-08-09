{
  stdenv,
  bashInteractive,
}:

# An /sbin/init that puts an interactive shell on the console, as an
# alternative to `init-stub` (which prints one line and powers the machine
# off). Select it with ILLUMOS_INIT=shell when running boot-qemu.sh.
#
# The shell is bash, and the *whole point* is that it is an ordinary
# dynamically linked illumos program: it exercises ld.so.1, the libc composite,
# readline, history, ncursesw, socket and nsl. Getting this far needed the
# Rock Ridge root (so the boot archive can carry symlinks and modes), ld.so.1's
# own dependencies installed beside it, `-ldl` resolving to libc rather than to
# the filter, and the two /dev-without-ZFS panics fixed -- see the commits for
# each.
#
# init itself is freestanding, for the same reason init-stub is: it has to work
# before we know that anything else does.
stdenv.mkDerivation {
  pname = "illumos-init-shell";
  version = "0";

  dontUnpack = true;

  # As in init-stub: keep it at $out/sbin/init rather than letting
  # move-sbin-to-bin.sh relocate it, because zone_initname is the literal
  # string "/sbin/init".
  dontMoveSbin = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -static -nostdlib -nostartfiles -ffreestanding \
        -fno-stack-protector -fno-pie -no-pie -e _start \
        -DPROG='"${bashInteractive}/bin/bash"' \
        -o init ${./init-shell.c}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 init "$out/sbin/init"
    runHook postInstall
  '';

  # -nostdlib means there is no interpreter to rewrite and nothing for RPATH
  # shrinking to do, and stripping a 2K static binary is pointless.
  dontStrip = true;
  dontPatchELF = true;

  # Nothing here uses libc, so none of the usual hardening applies; -fPIE in
  # particular fights -no-pie.
  hardeningDisable = [ "all" ];

  # The bash whose path is compiled in has to be in the boot archive too;
  # boot-qemu.sh stages this closure.
  passthru.shell = bashInteractive;
}
