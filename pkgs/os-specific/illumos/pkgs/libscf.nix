{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libuutil,
  libgen,
  libnvpair,
  libsmbios,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libdevinfo,
  libsec,
  libavl,
  libidmap,
  libnsl,
  libmd,
  libmp,
}:

# libscf.so.1 -- the client library for the Service Management Facility.
#
# This is the bottom of the SMF stack: everything else in cmd/svc talks to the
# repository through it. Three layers live here:
#
#   * `lowlevel.c`, the `scf_handle_*`/`scf_service_*`/`scf_property_*`
#     interface, which is a door-call RPC client (<door.h>, and the protocol
#     in usr/src/common/svc/repcache_protocol.h) speaking to svc.configd;
#   * `midlevel.c`, the `scf_simple_prop_*` convenience layer;
#   * `scf_tmpl.c`, the template interface -- the metadata that describes what
#     properties a service is *allowed* to have, which is what `svccfg
#     validate` checks a manifest against.
#
# Note the last one: the template machinery is in the library, not in svccfg,
# so it is the piece that makes semantic validation of a manifest possible at
# all.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libscf/amd64";
  pname = "libscf";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libscf"

    # `notify_params.o` and the repository door protocol are shared with
    # svc.configd and with the FMA notification code; Makefile.shared.com
    # compiles them out of $(COMDIR) = usr/src/common/svc.
    "usr/src/common/svc"

    # `lowlevel.c` includes <libzonecfg.h> (for the zone name that scopes a
    # repository handle), and <libzonecfg.h> in turn includes <libbrand.h>.
    # libbrand's header only reaches upstream builds through the proto area --
    # lib/libbrand's Makefile installs it into /usr/include -- so take it from
    # the source directory, as libdevinfo.nix does for <librcm.h>. Nothing
    # here links -lbrand or -lzonecfg; it is a header dependency only.
    "usr/src/lib/libbrand/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libuutil
    libgen
    libnvpair
    libsmbios
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/libbrand/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libuutil}/lib -R${libuutil}/lib -L${libgen}/lib -R${libgen}/lib -L${libnvpair}/lib -R${libnvpair}/lib -L${libsmbios}/lib -R${libsmbios}/lib -L${libdevinfo}/lib -R${libdevinfo}/lib -L${libsec}/lib -R${libsec}/lib -L${libavl}/lib -R${libavl}/lib -L${libidmap}/lib -R${libidmap}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # <libscf.h> and <libscf_priv.h> are installed into /usr/include by the
  # *top* lib/libscf Makefile, which we do not run: we build the amd64
  # subdirectory directly. `libscf-headers` already ships them for libc's
  # sake; ship them here too so that a consumer needs only this package.
  #
  # <repcache_protocol.h> goes along with them because svc.configd and
  # svc.startd are written against it and it has no home of its own.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libscf.so.1 "$out/lib/"
    ln -s libscf.so.1 "$out/lib/libscf.so"

    mkdir -p "$dev/include"
    cp ../inc/libscf.h ../inc/libscf_priv.h "$dev/include/"
    cp ../../../common/svc/repcache_protocol.h "$dev/include/"

    runHook postInstall
  '';
}
