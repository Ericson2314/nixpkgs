{
  mkDerivation,

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
  illumosLib = true;
  # Static only -- nothing here is ever linked, so illumos' ld is not needed.
  illumosLd = false;
  path = "usr/src/lib/ssp_ns/amd64";
  pname = "libssp_ns-illumos";

  extraPaths = [
    "usr/src/lib/ssp_ns"
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
