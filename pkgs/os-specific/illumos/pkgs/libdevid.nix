{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libdevinfo,
  # libdevinfo.so.1's own DT_NEEDEDs; the illumos link-editor insists on
  # finding a shared object's dependencies on the link path.
  libnvpair,
  libsec,
  libgen,
  libavl,
  libidmap,
  libuutil,
  libnsl,
  libmd,
  libmp,
}:

# libdevid.so.1 -- device identifiers: the persistent, location-independent
# names (`ddi_devid_t`) that let a disk be recognised after it has been moved
# to a different controller or target, plus the SCSI and SMP encodings that go
# with them.
#
# It is packaged here because devfsadm's disk and sgen link modules need it:
# disk_link.c builds /dev/dsk and /dev/rdsk names for SAS targets with
# `scsi_lun64_to_lun` and `scsi_wwnstr_to_wwn`, both of which live in
# common/devid/devid_scsi.c and are exported only from this library. Those are
# the only two entry points currently used, but the library is small -- one
# local source file plus the three shared with the kernel -- so it is packaged
# whole rather than carved up.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdevid/amd64";
  pname = "libdevid";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: devid names are needed before /usr is mounted,
    # so the library goes to /lib rather than /usr/lib.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdevid"

    # devid.o, devid_scsi.o and devid_smp.o are compiled straight out of the
    # code shared with the kernel, via Makefile.com's own explicit rules.
    "usr/src/common/devid"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libdevinfo
    # <libdevinfo.h> includes <libnvpair.h>, so the header has to be on the
    # include path even though nothing here calls into libnvpair directly.
    libnvpair
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to call `$(LD)` directly, and
  # libnsl.nix for why crti.o/crtn.o are named explicitly once the compiler
  # driver is out of the picture. Every `-L` gets a matching `-R`: without it
  # there is no DT_RUNPATH and no nix reference, so the dependency is absent
  # from the closure and never reaches the boot archive.
  #
  # common/devid/devid_scsi.c includes the library's own header as
  # <sys/libdevid.h>, and finds it in the proto area in an upstream build --
  # lib/libdevid/Makefile installs it to /usr/include/sys before anything is
  # compiled. There is no proto area here, so stage the one header under a
  # `sys/` directory and put that on the include path.
  preBuild = ''
    mkdir -p sysinclude/sys
    cp ../libdevid.h sysinclude/sys/

    makeFlagsArray+=("CPPFLAGS.first=-I$PWD/sysinclude -I${headers}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libdevinfo}/lib -R${libdevinfo}/lib -L${libnvpair}/lib -R${libnvpair}/lib -L${libsec}/lib -R${libsec}/lib -L${libgen}/lib -R${libgen}/lib -L${libavl}/lib -R${libavl}/lib -L${libidmap}/lib -R${libidmap}/lib -L${libuutil}/lib -R${libuutil}/lib -L${libnsl}/lib -R${libnsl}/lib -L${libmd}/lib -R${libmd}/lib -L${libmp}/lib -R${libmp}/lib \$(LDLIBS)")
  '';

  # The header is installed as <sys/libdevid.h> -- note the `sys/`, which is
  # how every consumer includes it -- by the *top* lib/libdevid Makefile, which
  # we do not run: the amd64 subdirectory is built directly.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdevid.so.1 "$out/lib/"
    ln -s libdevid.so.1 "$out/lib/libdevid.so"

    mkdir -p "$dev/include/sys"
    cp ../libdevid.h "$dev/include/sys/"

    runHook postInstall
  '';
}
