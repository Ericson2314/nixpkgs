{
  lib,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  perl,
  gnum4,
}:

# The illumos link-editor, built as a *native* program for the build host.
#
# GNU ld cannot parse illumos `$mapfile_version 2` mapfiles, which blocks
# linking libc.so.1 (and anything else with a versioning mapfile). illumos
# already carries a native build of the link-editor for exactly this reason,
# under usr/src/tools/sgs -- it is what a cross-build of illumos-on-illumos
# uses. This packages that.
mkDerivation {
  pname = "ld-native";

  path = "usr/src/tools/sgs";
  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/tools/Makefile.tools"
    "usr/src/tools/Makefile.targ"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # Only the pieces of cmd/sgs that the native link-editor needs; naming the
    # whole directory would drag in (and rebuild on) lorder, ar, elfdump, ...
    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/Makefile.sub"
    "usr/src/cmd/sgs/common"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/ld"
    "usr/src/cmd/sgs/libconv"
    "usr/src/cmd/sgs/libelf"
    "usr/src/cmd/sgs/liblddbg"
    "usr/src/cmd/sgs/libld"
    "usr/src/cmd/sgs/messages"
    "usr/src/cmd/sgs/tools/libconv_mk_report_bufsize.pl"

    "usr/src/common/avl"
    "usr/src/common/elfcap"
    "usr/src/common/sgsrtcid"

    "usr/src/head"
    "usr/src/uts/common/sys"
    "usr/src/uts/common/krtld"
    "usr/src/uts/sparc/krtld"
    "usr/src/uts/intel/ia32/krtld"
    "usr/src/uts/intel/amd64/krtld"
    "usr/src/uts/sparc/sys"
    "usr/src/uts/intel/sys"

    "usr/src/lib/libc/inc"
    "usr/src/lib/libdemangle/common"
  ];

  makeFlags = [
    # ROOTONBLD is where this installs; ONBLD_TOOLS is where its own makefiles
    # then look for the sgsmsg it just built. tools/sgs/Makefile forwards both
    # to the sub-makes.
    "ROOTONBLD=${builtins.placeholder "out"}"
    "ONBLD_TOOLS=${builtins.placeholder "out"}"

    # illumos' MACH/MACH64 are not uname strings: on x86 they are i386/amd64,
    # and the makefiles index directories with them.
    "MACH=i386"
    "MACH64=amd64"
  ];

  # `make` with no target picks the first one, `all`, and dmake does not apply
  # `all := TARGET= install` to it -- the sub-makes then get an empty target
  # and silently build nothing. Naming `install` explicitly avoids that.
  buildFlags = [ "install" ];
  dontInstall = true;

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    perl
    gnum4
  ];

  # The build installs as it goes, so the target directories have to exist
  # before it starts rather than in preInstall.
  preBuild = ''
    mkdir -p $out/bin/i386 $out/bin/amd64 $out/lib/i386/64 $out/man/man1onbld
  '';

  # The onbld layout puts the tool under bin/$(MACH64). $ORIGIN in its runpath
  # resolves from the real path, so a symlink at the conventional place still
  # finds the libraries next to it.
  postFixup = ''
    ln -s amd64/ld $out/bin/ld
  '';

  meta.platforms = lib.platforms.unix;
}
