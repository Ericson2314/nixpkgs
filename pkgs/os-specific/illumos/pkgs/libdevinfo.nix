{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libnvpair,
  libsec,
  libgen,
  # libsec.so.1's and libnvpair.so.1's own DT_NEEDEDs; the illumos
  # link-editor insists on finding a shared object's dependencies on the link
  # path.
  libavl,
  libidmap,
  libuutil,
  libnsl,
  libmd,
  libmp,
}:

# libdevinfo.so.1 -- the device-information library: the `di_init`/`di_node`
# snapshot walker over the kernel device tree, the /dev link database
# (`di_devlink_*`), `devfsmap`, and `di_finddev`.
#
# It is packaged here only because `libsmbios.so.1` links `-ldevinfo`, and
# libscf links `-lsmbios` on x86. Nothing forces the device-tree side of it to
# be exercised for that path -- see libsmbios.nix.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdevinfo/amd64";
  pname = "libdevinfo";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdevinfo"

    # `devinfo_retire.c` includes <librcm.h>. The RCM library is `dlopen`ed at
    # run time -- there is no `-lrcm` here -- but the header is still needed to
    # compile, and it reaches upstream builds only via the proto area, since
    # lib/librcm's own Makefile installs it into /usr/include. Take it from the
    # source directory, as libnsl.nix and libsecdb.nix do for their own
    # not-quite-public headers.
    "usr/src/lib/librcm"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libnvpair
    libsec
    libgen
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
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I\$(SRC)/lib/librcm")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libnvpair}/lib -R${libnvpair}/lib -L${libsec}/lib -R${libsec}/lib -L${libgen}/lib -R${libgen}/lib -L${libavl}/lib -R${libavl}/lib -L${libidmap}/lib -R${libidmap}/lib -L${libuutil}/lib -R${libuutil}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # <libdevinfo.h> is installed into /usr/include by the *top* lib/libdevinfo
  # Makefile, which we do not run: we build the amd64 subdirectory directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdevinfo.so.1 "$out/lib/"
    ln -s libdevinfo.so.1 "$out/lib/libdevinfo.so"

    mkdir -p "$dev/include"
    cp ../libdevinfo.h "$dev/include/"

    runHook postInstall
  '';
}
