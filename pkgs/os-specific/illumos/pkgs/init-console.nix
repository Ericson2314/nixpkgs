{
  stdenv,
  illumos,
}:

# A debugging /sbin/init: opens the console the way init-shell does, puts it on
# fds 0/1/2, and execs the real init in the same process so it is still pid 1.
#
# It exists because real init writes its diagnostics to /dev/console and
# /dev/msglog, neither of which exists without devfsadm, so an early failure is
# completely silent -- all the kernel reports is "init(8) exited on fatal
# signal 9", a couple of hundred times a second. Select it in the image in
# place of `illumos.init` to find out what init is actually complaining about.
#
# Freestanding for the same reason the other inits are: it has to work before
# anything else is known to.
stdenv.mkDerivation {
  pname = "illumos-init-console";
  version = "0";

  dontUnpack = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -static -nostdlib -nostartfiles -ffreestanding \
        -fno-stack-protector -fno-pie -no-pie -e _start \
        -DPROG='"${illumos.init}/sbin/init"' \
        -o init ${./init-console.c}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/sbin" "$out/bin"
    cp init "$out/sbin/init"
    chmod 755 "$out/sbin/init"
    ln -s ../sbin/init "$out/bin/init"
    runHook postInstall
  '';

  # As for the other inits: zone_initname is the literal "/sbin/init".
  dontMoveSbin = true;

  # -nostdlib, so there is no interpreter to rewrite and nothing to strip.
  dontStrip = true;
  dontPatchELF = true;

  hardeningDisable = [ "all" ];

  # The real init it execs has to be staged alongside it.
  passthru.realInit = illumos.init;
}
