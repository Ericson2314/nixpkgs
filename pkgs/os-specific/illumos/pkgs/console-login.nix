{
  stdenv,
  bashInteractive,
}:

# A console "getty" for an image that has none of the machinery a console login
# normally comes from: it opens the console by its /devices path, pushes ldterm
# and ttcompat onto the bare asy(4D) stream, sets a sane termios and runs a root
# shell on it, respawning the shell when it exits.
#
# On a real system this is svc:/system/console-login:default running ttymon.
# Here svc.configd cannot open a repository, so svc.startd starts no services at
# all; ttymon, login and devfsadm are unpackaged; and autopush is not there to
# give the console a line discipline. See the header comment in console-login.c
# for each of those, and for why the inittab entry has to be `sysinit` rather
# than `respawn`.
#
# Freestanding, like the inits: this is part of getting *to* a prompt, so it
# must not depend on the userland it exists to let you inspect. The shell it
# execs, by contrast, is an ordinary dynamically linked illumos bash.
stdenv.mkDerivation {
  pname = "illumos-console-login";
  version = "0";

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -static -nostdlib -nostartfiles -ffreestanding \
        -fno-stack-protector -fno-pie -no-pie -e _start \
        -DPROG='"${bashInteractive}/bin/bash"' \
        -o console-login ${./console-login.c}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 console-login "$out/sbin/console-login"
    runHook postInstall
  '';

  # /etc/inittab names this by an absolute /sbin path, and the boot archive
  # symlinks it there; keep it out of move-sbin-to-bin.sh's way.
  dontMoveSbin = true;

  # -nostdlib means there is no interpreter to rewrite and no runpath to
  # shrink, and stripping a 3K static binary is pointless.
  dontStrip = true;
  dontPatchELF = true;

  # Nothing here uses libc, so none of the usual hardening applies; -fPIE in
  # particular fights -no-pie.
  hardeningDisable = [ "all" ];

  # The bash whose path is compiled in has to be in the boot archive too.
  passthru.shell = bashInteractive;
}
