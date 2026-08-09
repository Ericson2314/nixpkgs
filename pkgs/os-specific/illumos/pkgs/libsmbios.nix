{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libdevinfo,
  # libdevinfo.so.1's own DT_NEEDEDs, and theirs; the illumos link-editor
  # insists on finding a shared object's dependencies on the link path.
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

# libsmbios.so.1 -- the SMBIOS/DMI table reader: `smbios_open` over
# /dev/smbios (or a file), and the `smbios_info_*` accessors that decode the
# firmware's system, chassis and processor structures.
#
# Needed because `lib/libscf/Makefile.com` has
#
#     LDLIBS_i386 += -lsmbios
#
# libscf's one use of it is `scf_is_fb_blacklisted()` in `highlevel.c`, which
# reads the platform name out of SMBIOS to decide whether fast reboot is
# allowed on this machine. Small, but it is a real interface of the library,
# so it is built rather than stubbed.
#
# The bulk of the decoding tables are generated: `mktables.sh` turns the
# `SMB_*` #defines in <sys/smbios.h> into `smb_tables.c`. That is a plain
# shell/awk script over a header, so it runs on the build host unchanged.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libsmbios/amd64";
  pname = "libsmbios";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libsmbios"

    # `smb_error.o`, `smb_info.o` and `smb_open.o` are compiled out of the
    # code shared with the kernel's SMBIOS driver, via Makefile.com's
    # `objs/%.o pics/%.o: ../../../common/smbios/%.c` rule. `mktables.sh`
    # lives there too.
    "usr/src/common/smbios"

    # `mktables.sh`'s input is $(SRC)/uts/common/sys/smbios.h.
    "usr/src/uts/common/sys"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libdevinfo
    # <libdevinfo.h> includes <libnvpair.h>.
    libnvpair
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture.
  # `Makefile.com`'s rule for `smb_tables.c` is `sh mktables.sh ...`, and the
  # script builds the C source with `echo "\nconst char *\n..."`: it assumes
  # the SVR4/XPG `echo`, which expands backslash escapes itself. bash's `echo`
  # does not, so every `\n` and `\t` reaches the compiler literally and the
  # generated file comes out as a wall of "stray '\' in program".
  #
  # `bash -O xpg_echo` restores exactly the `echo` behaviour the script was
  # written for, so the script itself needs no changes. Generating the file
  # ahead of make does not work: `.KEEP_STATE` makes dmake re-run every rule
  # whose recorded command line it has not seen before, and on a fresh build
  # directory that is all of them, so the rule has to be the thing that
  # changes.
  postPatch = ''
    substituteInPlace usr/src/lib/libsmbios/Makefile.com \
      --replace-fail 'sh $(COMMON_SRCDIR)/mktables.sh' \
                     'bash -O xpg_echo $(COMMON_SRCDIR)/mktables.sh'
  '';

  preBuild = ''
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${libdevinfo}/lib -L${libnvpair}/lib -L${libsec}/lib -L${libgen}/lib -L${libavl}/lib -L${libidmap}/lib -L${libuutil}/lib -L${libnsl}/lib -L${libmd}/lib -L${libmp}/lib \$(LDLIBS)")
  '';

  # <smbios.h> here is the *library* header (lib/libsmbios/common/smbios.h),
  # which is what libscf's highlevel.c includes; the kernel's
  # uts/common/sys/smbios.h is a different file and is already in `headers`.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libsmbios.so.1 "$out/lib/"
    ln -s libsmbios.so.1 "$out/lib/libsmbios.so"

    mkdir -p "$dev/include"
    cp ../common/smbios.h "$dev/include/"

    runHook postInstall
  '';
}
