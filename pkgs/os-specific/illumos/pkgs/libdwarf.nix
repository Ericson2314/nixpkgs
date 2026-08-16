{
  lib,
  stdenv,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,

  buildPackages,

  # Only used by the illumos-hosted build; see the split at the bottom.
  crt,
  headers,
  libcMinimal,
  libssp_ns,
  sgs-libelf,
  zlib,
}:

# The libdwarf that the CTF tools link against, built as a *native* library for
# the build host.
#
# This is illumos' vendored copy of David Anderson's libdwarf (20200612), not
# the one in nixpkgs: `ctfconvert` consumes the pre-0.x API (`dwarf_elf_init()`
# and friends), which the modern releases no longer provide.
#
# Everything here is a build-host program, so nothing depends on the illumos
# cross toolchain -- hence `noCC`, plus the host compiler by way of
# `depsBuildBuild`. illumos' makefiles find it through `$CC_FOR_BUILD`; see
# `NATIVE_PRIMARY_CC_PATH` in usr/src/Makefile.master.
let
  forIllumos = stdenv.hostPlatform.isSunOS;
in
mkDerivation (
  {
  pname = "libdwarf";

  # The i386 directory is entered directly rather than through
  # ../Makefile's `SUBDIRS = $(MACH)` recursion, which does not forward
  # $ROOTONBLD to the sub-make. Despite the name the build is 64-bit; see the
  # comment in tools/ctf/Makefile.ctf.native.
  path = if forIllumos then "usr/src/lib/libdwarf/amd64" else "usr/src/tools/ctf/dwarf/i386";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"

    # The whole of tools/ctf rather than the individual makefiles: it is a
    # small, self-contained subtree, and naming pieces of it would not work
    # anyway -- Makefile.ctf.native does not exist upstream, it is created by
    # the patch, so filterSource cannot copy it by name.
    "usr/src/tools/ctf"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/lib/libdwarf/common"

    # Reached by the -idirafter in Makefile.ctf.native: the force-included
    # native_compat.h wants <sys/isa_defs.h> and <sys/ccompile.h>, which no
    # foreign libc has.
    "usr/src/uts/common/sys"
    "usr/src/head"
  ]
  # Only the illumos-hosted build links a shared object, so only it needs the
  # link-editor mapfiles. Kept conditional so that adding them leaves the
  # build-host derivation's inputs untouched -- that is the one the CTF tools
  # use, and rebuilding it rebuilds libc and the kernel behind it.
  ++ lib.optionals forIllumos [
    # The illumos-hosted build needs the library directory itself, not just
    # common/: its amd64 Makefile includes ../Makefile.com.
    "usr/src/lib/libdwarf"
    "usr/src/common/mapfiles"
  ];

  meta.platforms = lib.platforms.unix;
  }
  // (
    if forIllumos then
      {
        # The illumos-hosted build is an ordinary cross-compiled shared
        # library. None of the build-host machinery below applies: every one
        # of those attributes exists to make a *native* library, and using
        # them here compiles target sources with the host gcc.
        libcMinimal = true;
        illumosLib = true;

        outputs = [
          "out"
          "dev"
        ];

        buildInputs = [
          headers
          crt
          libcMinimal
          sgs-libelf
          zlib
        ];

        env.NIX_CFLAGS_COMPILE = builtins.toString [
          "-B${crt}/lib"
          "-Wno-error"
        ];

        buildFlags = [ "all" ];

        # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
        # directly, and libnsl.nix for why crti.o/crtn.o have to be named
        # explicitly once the compiler driver is out of the picture.
        preBuild = ''
          makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o -L${libcMinimal}/lib -L${libssp_ns}/lib -L${sgs-libelf}/lib -R${sgs-libelf}/lib -L${zlib}/lib -R${zlib}/lib \$(LDLIBS)")
        '';

        installPhase = ''
          runHook preInstall

          mkdir -p "$out/lib"
          cp libdwarf.so.1 "$out/lib/"
          ln -s libdwarf.so.1 "$out/lib/libdwarf.so"

          mkdir -p "$dev/include"
          cp ../common/dwarf.h ../common/libdwarf.h "$dev/include/"

          runHook postInstall
        '';
      }
    else
      {
        noCC = true;

        makeFlags = [
          "ROOTONBLD=${builtins.placeholder "out"}"
          "MACH=i386"
          "MACH64=amd64"
        ];

        buildFlags = [ "install" ];
        dontInstall = true;

        extraNativeBuildInputs = [
          cw
        ];

        # Build-platform dependencies, not host-platform ones: the library
        # produced here runs on the machine doing the build.
        depsBuildBuild = [
          buildPackages.stdenv.cc
          buildPackages.elfutils
          buildPackages.zlib
        ];

        # The build installs as it goes, so the target directory has to exist
        # before it starts rather than in preInstall.
        preBuild = ''
          mkdir -p $out/lib/i386
        '';
      }
  )
)
