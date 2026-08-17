{
  lib,
  mkDerivation,

  headers,
}:

# klog(1) -- drain and print the kernel's message log.
#
# Not an illumos program: a few dozen lines written here, for the same reason
# as `ditree`. illumos has no readable kernel ring buffer -- no /dev/kmsg, no
# dmesg(1) that works without a running syslog. cmn_err(9F) output goes to the
# console driver and to log(4D), and log(4D) holds everything printed before a
# console logger registers, delivering the backlog to whoever registers first.
# On a bring-up system where the console is a serial line we cannot always read
# and syslogd does not run, that backlog is the only copy of the early boot
# messages -- including whatever a failing attach(9E) printed.
#
# syslogd(8) is the real program for this, but it needs a config file, a
# writable /var, a door server and a thread pool. This is just the part that
# registers with I_CONSLOG and prints what comes back.
#
# Retire it when syslogd runs as an SMF service and its output is reachable.
mkDerivation {
  pname = "klog";
  noLibc = false;

  # No illumos source subtree -- the C is here. `path` still has to name
  # something in the gate for the shared mkDerivation plumbing; this points at
  # the driver whose protocol the program speaks, though nothing there is
  # compiled.
  path = "usr/src/uts/common/io";

  buildInputs = [ headers ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -o klog ${./klog.c}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp klog $out/bin/klog
    chmod 755 $out/bin/klog
    runHook postInstall
  '';

  meta = {
    description = "Drain and print illumos kernel messages from log(4D)";
    mainProgram = "klog";
  };
}
