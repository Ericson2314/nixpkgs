{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libnvpair,
}:

# librcm.so.1 -- the client side of the Reconfiguration Coordination Manager:
# `rcm_alloc_handle`, `rcm_request_offline`, `rcm_notify_event` and friends,
# which let a caller ask rcm_daemon(8) whether a device or resource may be
# taken away and be told when one appears or leaves.
#
# Nothing here wants RCM for its own sake -- rcm_daemon is not packaged, and
# without it these calls simply fail rather than blocking. It is packaged
# because `libdladm` links `-lrcm` unconditionally (it registers datalink
# consumers so that a NIC cannot be unplugged out from under a link), and the
# illumos link-editor will not produce libdladm.so.1 without finding it.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/librcm/amd64";
  pname = "librcm";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: librcm is a /lib library, not /usr/lib, since
    # its consumers (libdladm, and thence ifconfig) live in /sbin.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/librcm"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libnvpair
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # `librcm_event.c` includes <libnvpair.h> -- the event payloads are nvlists
  # packed across the daemon's door -- so libnvpair's `dev` output has to be on
  # the include path explicitly.
  #
  # librcm's own <librcm.h> needs the same treatment for a different reason:
  # `librcm_impl.h` includes it with angle brackets, expecting to find it in
  # the proto area, and Makefile.com adds no `-I` of its own (unlike most
  # libraries here it has no `SRCDIR`; the sources sit directly in
  # lib/librcm). Point at the source directory instead.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libnvpair.dev}/include -I\$(SRC)/lib/librcm")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnvpair}/lib -R${libnvpair}/lib \$(LDLIBS)")
  '';

  # The three headers are the *top* lib/librcm Makefile's `HDRS`, which we do
  # not run: the amd64 subdirectory is built directly. `librcm_impl.h` is in
  # upstream's install list too -- rcm_daemon and its modules share the wire
  # format it declares -- so it is copied along with the public ones.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp librcm.so.1 "$out/lib/"
    ln -s librcm.so.1 "$out/lib/librcm.so"

    mkdir -p "$dev/include"
    cp ../librcm.h ../librcm_impl.h ../librcm_event.h "$dev/include/"

    runHook postInstall
  '';
}
