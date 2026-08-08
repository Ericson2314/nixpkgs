{ stdenv }:

# A stand-in for /sbin/init, so that the boot can be taken past
# vfs_mountroot() and all the way into user mode.
#
# illumos' real init (usr/src/cmd/init) links against -lpam -lbsm -lcontract
# -lscf: PAM, the basic security module, the contract filesystem's library and
# SMF's repository client. None of those is ported yet, and none of them is
# needed to demonstrate that the kernel can exec a process out of the root
# filesystem -- which is the milestone this exists to reach.
#
# As of this commit the kernel does not actually reach init -- it stops in
# consconfig() -- so this is aspirational: it is checked in so that the boot
# image has something to exec, and so that the next person does not have to
# reinvent it.
#
# The C is freestanding (raw `syscall` traps, `-nostdlib`), so this needs
# nothing from the illumos userland at all: no libc, no crt1.o, no ld.so.1.
# That keeps it honest as a test of the *kernel*.
stdenv.mkDerivation {
  pname = "illumos-init-stub";
  version = "0";

  dontUnpack = true;

  # `move-sbin-to-bin.sh` would relocate $out/sbin/init to $out/bin and leave
  # $out/sbin a symlink. The boot image wants it at a stable path, and the
  # kernel's zone_initname is literally "/sbin/init", so keep it in sbin.
  dontMoveSbin = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -static -nostdlib -nostartfiles -ffreestanding \
        -fno-stack-protector -fno-pie -no-pie -e _start \
        -o init ${./init-stub.c}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 init "$out/sbin/init"
    runHook postInstall
  '';

  # -nostdlib means there is nothing for RPATH shrinking or the interpreter
  # rewrite to act on, and stripping a 1.4K static binary is pointless.
  dontStrip = true;
  dontPatchELF = true;

  # Nothing here uses libc, so none of the usual hardening flags apply; the
  # cc-wrapper's -fPIE in particular fights -no-pie.
  hardeningDisable = [ "all" ];
}
