{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libavl,
  libumem,
  libidspace,
  libnvpair,
  libmd,
  librename,
}:

# libvarpd.so.1 -- the "variable ARP daemon" library out of lib/varpd/libvarpd.
# It is the framework half of illumos' overlay-device plumbing: it loads varpd
# plugins, keeps the per-instance property tables, serves the door protocol
# that `varpd`/`dladm` use, and answers the kernel's overlay target-cache
# lookups (`libvarpd_overlay.c`) and the proxy ARP/NDP responder
# (`libvarpd_arp.c`).
#
# It is packaged here purely as a link-time dependency: `libdladm` links
# `-lvarpd` for the `dladm create-overlay` family of entry points in
# `libdloverlay.c`. No overlay is configured in this VM, and no plugin is
# packaged, so at run time none of this is reached -- but the illumos
# link-editor runs with -zdefs and insists on resolving every symbol, so the
# real library has to be present rather than a stub.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/varpd/libvarpd/amd64";
  pname = "libvarpd";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libvarpd is a /lib library, because dladm and
    # ifconfig -- which reach it through libdladm -- live in /sbin.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/varpd/libvarpd"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libavl
    libumem
    libidspace
    libnvpair
    libmd
    librename
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # The four `dev` outputs on the include path are the headers this library's
  # sources include by angle brackets and would otherwise expect to find in
  # the proto area: <umem.h> (libvarpd allocates its instance and plugin state
  # from a umem cache), <libidspace.h> (instance ids come from an id space),
  # <libnvpair.h> (the persisted property lists) and <librename.h> (the
  # atomic-rename helper used when rewriting the persistence file).
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libumem.dev}/include -I${libidspace.dev}/include -I${libnvpair.dev}/include -I${librename.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libavl}/lib -R${libavl}/lib -L${libumem}/lib -R${libumem}/lib -L${libidspace}/lib -R${libidspace}/lib -L${libnvpair}/lib -R${libnvpair}/lib -L${libmd}/lib -R${libmd}/lib -L${librename}/lib -R${librename}/lib \$(LDLIBS)")
  '';

  # The headers are the *top* lib/varpd/libvarpd Makefile's install list, which
  # we do not run: the amd64 subdirectory is built directly.
  # `libvarpd_provider.h` is the plugin ABI and `libvarpd_client.h` the door
  # client ABI; both are public, and libdladm uses the latter.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libvarpd.so.1 "$out/lib/"
    ln -s libvarpd.so.1 "$out/lib/libvarpd.so"

    mkdir -p "$dev/include"
    cp ../common/libvarpd.h ../common/libvarpd_client.h \
      ../common/libvarpd_provider.h "$dev/include/"

    runHook postInstall
  '';
}
