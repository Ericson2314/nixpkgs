{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,

  crt,
  headers,
}:

# libssp_ns.a -- the non-shared half of the stack protector, holding
# __stack_chk_fail_local. Makefile.master:391 puts -lssp_ns into LDSTACKPROTECT
# and Makefile.lib:178 appends that to every library's LDLIBS, so anything
# built with the stack protector on needs this at link time.
#
# FreeBSD's libc join includes libssp_nonshared for the same reason.
#
# A single object, and static only, so it needs none of the shared-library
# machinery the other libraries do.
mkDerivation {
  noLibc = true;
  path = "usr/src/lib/ssp_ns/amd64";
  pname = "libssp_ns-illumos";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/ssp_ns"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ];

  buildInputs = [
    headers
    crt
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "CPPFLAGS.first=-I${headers}/include"
    "MACH=i386"
    "MACH64=amd64"
    # Building the stack-protector helper itself with the stack protector on
    # would be circular.
    "STACKPROTECT=none"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libssp_ns.a "$out/lib/"

    runHook postInstall
  '';
}
