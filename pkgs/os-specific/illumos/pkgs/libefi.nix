{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libuuid,
  libsmbios,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's own dependencies on the link path. libuuid
  # embeds a MAC address in a version-1 UUID and so drags in the whole
  # dlpi/dladm cluster (see libuuid.nix), and libsmbios brings libdevinfo's.
  libsocket,
  libnsl,
  libdlpi,
  libdladm,
  libinetutil,
  libdevinfo,
  libscf,
  librcm,
  libnvpair,
  libexacct,
  libkstat,
  libpool,
  libvarpd,
  libgen,
  libuutil,
  libsec,
  libavl,
  libidmap,
  libumem,
  libidspace,
  librename,
  libxml2,
  libmd,
  libmp,
}:

let
  runtimeLibs = [
    libuuid
    libsmbios
    libsocket
    libnsl
    libdlpi
    libdladm
    libinetutil
    libdevinfo
    libscf
    librcm
    libnvpair
    libexacct
    libkstat
    libpool
    libvarpd
    libgen
    libuutil
    libsec
    libavl
    libidmap
    libumem
    libidspace
    librename
    libxml2.out
    libmd
    libmp
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libefi.so.1 -- reading and writing EFI/GPT disk labels: `efi_alloc_and_read`,
# `efi_write`, `efi_alloc_and_init`, and the CRC32 the GPT header carries.
#
# This is how `zpool` labels a whole disk. `zpool create tank c1t0d0` does not
# hand the raw device to the kernel: `zpool_label_disk()` in libzfs writes a
# GPT with one big `V_USR` slice through libefi and then gives ZFS the slice.
# `libzutil`'s import scan reads labels back the same way to decide what a
# device is.
#
# Its own link is short -- `-luuid -lsmbios -lc` -- but libuuid's dependency
# closure is not, hence the list above. Both are genuine: the GPT partition
# and disk GUIDs are UUIDs, and libsmbios supplies the system identity that
# `efi_alloc_and_init` stamps into a new label.
#
# No `dev` output is needed: the public interface is <sys/efi_partition.h>,
# which lives under usr/src/uts and so is already in the `headers` package.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libefi/amd64";
  pname = "libefi";

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: a /lib library, because the label readers have
    # to work before /usr is mounted -- which for a ZFS root is the whole
    # point.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libefi"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libuuid
    libsmbios
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
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libsmbios.dev}/include")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libefi.so.1 "$out/lib/"
    ln -s libefi.so.1 "$out/lib/libefi.so"

    runHook postInstall
  '';
}
