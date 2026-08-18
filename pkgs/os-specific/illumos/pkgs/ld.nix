{
  lib,
  stdenv,
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  perl,
  gnum4,
  sgsmsg,

  libcompat,
  headers,
  crt,
  libcMinimal,
  sgs-libconv,
  sgs-libelf,
  sgs-liblddbg,
  sgs-libld,
}:

# The illumos link-editor, ld(1).
#
# GNU ld cannot parse illumos `$mapfile_version 2` mapfiles, which blocks
# linking libc.so.1 (and anything else with a versioning mapfile), and it
# rejects -Bdirect outright. So essentially every illumos link goes through
# this.
#
# There is *one* attribute, and it builds whichever of illumos' two ld source
# trees suits the platform it is being built for. Which platform that is comes
# from the package set, not from the name: `buildPackages.illumos.ld` is the
# link-editor that runs on the build machine (the usual case here -- a Linux
# binary emitting illumos objects), while `illumos.ld` in a cross set is one
# that would run on illumos. Do not reintroduce a second attribute to express
# that; the attribute path already does, and splicing is what picks between
# them.
#
#  o	For the build platform, usr/src/tools/sgs. This is illumos' own
#	bootstrapping arrangement: the same link-editor sources compiled
#	-DNATIVE_BUILD against tools/sgs/native/native_compat.h, with its own
#	libld/libconv/liblddbg/libelf built alongside, so that it depends on
#	nothing illumos-hosted. It is what an illumos-on-illumos cross-build
#	uses, and the only form that can exist before we have a libc.
#
#  o	For an illumos host, usr/src/cmd/sgs/ld -- the ld(1) that actually
#	ships, linked against the separately-packaged sgs-lib* shared
#	libraries.
#
# The tools/sgs vs cmd/sgs split is illumos' internal bootstrapping detail; in
# nixpkgs terms both produce the same logical package.
let
  forIllumos = stdenv.hostPlatform.isSunOS;

  # Read before the component's own Makefile either way.
  commonPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/Makefile.sub"
    "usr/src/cmd/sgs/common"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/ld"
    "usr/src/cmd/sgs/messages"

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

in
mkDerivation (
  {
    pname = "ld";

    # For an illumos host, usr/src/cmd/sgs/ld/amd64 -- the amd64 subdirectory
    # directly, not cmd/sgs/ld: the parent's `cd amd64; make all` recursion
    # does not forward our command-line macros, so ONBLD_TOOLS below would
    # revert to its /ws/onnv-tools default. Every sibling here (sgs-libconv,
    # sgs-libld, rtld) enters .../amd64 for the same reason.
    #
    # For the build platform, usr/src/tools/sgs. This is illumos' own
    # bootstrapping arrangement: the same link-editor sources compiled
    # -DNATIVE_BUILD against tools/sgs/native/native_compat.h, with its own
    # libld/libconv/liblddbg/libelf built alongside, so that it depends on
    # nothing illumos-hosted. It is what an illumos-on-illumos cross-build
    # uses, and the only form that can exist before we have a libc.
    path = "usr/src/cmd/sgs/ld/amd64";

    # tools/sgs builds the support libraries itself rather than linking the
    # illumos-hosted ones, so it needs their sources too.
    extraPaths =
      commonPaths
      ++ (
        if forIllumos then
          [ "usr/src/common/mapfiles" ]
        else
          [
            #"usr/src/tools/Makefile.tools"
            #"usr/src/tools/Makefile.targ"

            ## Only the pieces of cmd/sgs that the native link-editor needs; naming the
            ## whole directory would drag in (and rebuild on) lorder, ar, elfdump, ...
            #"usr/src/cmd/sgs/libconv"
            #"usr/src/cmd/sgs/libelf"
            #"usr/src/cmd/sgs/liblddbg"
            #"usr/src/cmd/sgs/libld"
            #"usr/src/cmd/sgs/tools/libconv_mk_report_bufsize.pl"
          ]
      );

    nativeBuildInputs = [
      illumosSetupHook
      make
      install
      cw
      perl
      gnum4
      sgsmsg
    ];

    # headers/crt/libcMinimal are illumos-hosted only -- `headers` is
    # `meta.platforms = [ "x86_64-solaris2.11" ]` -- so naming them
    # unconditionally makes the build-platform `ld`, and through it the whole
    # set, refuse to evaluate. The native link-editor needs none of them: it
    # compiles against the host libc, which is the point of -DNATIVE_BUILD.
    #
    # The sgs support libraries are named for both platforms, because each now
    # has a build-platform instance of its own.
    buildInputs = lib.optionals forIllumos [
      headers
      crt
      libcMinimal
    ] ++ [
      sgs-libconv
      sgs-libelf
      sgs-liblddbg
      sgs-libld
    ];
  }
  // lib.optionalAttrs forIllumos {
    libcMinimal = true;

    illumosLib = true;

    env.NIX_CFLAGS_COMPILE = builtins.toString [
      "-B${crt}/lib"
      "-Wno-error"
    ];

  }
  // lib.optionalAttrs (!forIllumos) {
    # tools/sgs installs into the onbld $(ROOTONBLD)/bin/$(MACH64) layout, so
    # it needs MACH set even though it is built for the build host.
    illumosOnbldMach = true;

    # `make` with no target picks the first one, `all`, and dmake does not
    # apply `all := TARGET= install` to it -- the sub-makes then get an empty
    # target and silently build nothing. Naming `install` explicitly avoids
    # that.
    # The onbld layout puts the tool under bin/$(MACH64). $ORIGIN in its
    # runpath resolves from the real path, so exec'ing it from bin/ld still
    # finds the libraries next to it.
    #
    # POSIXLY_CORRECT is essential, not cosmetic, and belongs here rather than
    # in a caller's wrapper: it is a property of running this binary at all.
    # illumos ld parses its command line with getopt(3), and glibc's getopt
    # permutes argv so that non-option arguments end up *after* the options.
    # `ld a.o -L/x -lfoo` is therefore silently reordered into
    # `ld -L/x -lfoo a.o`, so every archive is searched before the objects that
    # reference it, no archive member is ever extracted, and the link fails
    # with "symbol referencing errors" naming symbols that are plainly present
    # in the archive. (`ld -Dfiles` shows the archive being processed before
    # the .o files.) POSIXLY_CORRECT makes glibc's getopt stop permuting and
    # behave the way the Solaris one does.
    #
    # Shared-library-only links never trip over this, which is why libc and
    # libm uilt fine for a long time before it surfaced in the ld.so.1 link.
    postFixup = ''
      cat > $out/bin/ld <<EOF
      #!${buildPackages.runtimeShell}
      export POSIXLY_CORRECT=1
      exec "$out/bin/ld-unwrapped" "\$@"
      EOF
      chmod +x $out/bin/ld
    '';
  }
  // {
    # `all` on both arms. The native side used to build the `install` target,
    # because it relied on tools/sgs installing into the onbld proto layout as
    # it went. Building cmd/sgs/ld directly there is nothing to install but the
    # one binary, and installPhase does that.
    buildFlags = [ "all" ];

    # Identical on both arms now: `path` is the amd64 directory itself, so the
    # binary is ./ld. It installs under a distinct name because postFixup puts
    # the wrapper at bin/ld -- installing both as `ld` is how you get a wrapper
    # that execs itself, which is an unkillable hang rather than an error.
    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      cp ld "$out/bin/ld-unwrapped"

      runHook postInstall
    '';

    makeFlags =
      if forIllumos then
        [
          # $(SGSMSG) is $(ONBLD_TOOLS)/bin/$(MACH)/sgsmsg, which otherwise
          # defaults to the /ws/onnv-tools path a real onbld build would use. The
          # build-platform `ld` already builds and installs sgsmsg, so point at
          # that -- the same thing sgs-libconv and friends do. This is a
          # cross-package-set reference, and it terminates: the attribute it names
          # is the tools/sgs branch above, which needs nothing from here.
          "ONBLD_TOOLS=${buildPackages.illumos.ld}"

          # $(MAPFILE.NGB) is common/mapfiles/gen/$(MACH)_gcc_map.noexeglobs,
          # which common/mapfiles/gen builds by compiling and *running* a helper
          # (its Makefile links against NATIVE_LIBS += libc.so). It is a link-time
          # assertion that the object exports no writable globals, not something
          # ld needs to function, so drop it rather than add another
          # compile-and-run bootstrap step.
          "MAPFILE.NGB="
        ]
      else
        [
          # ROOTONBLD is where this installs; ONBLD_TOOLS is where its own
          # makefiles then look for the sgsmsg it just built. tools/sgs/Makefile
          # forwards both to the sub-makes.
          "ROOTONBLD=${builtins.placeholder "out"}"

          # cmd/sgs/Makefile.com appends $(COMPAT_CPPFLAGS) to CPPFLAGS. It is
          # empty for an illumos-hosted build; here it is what lets the very
          # same makefiles compile against the host libc, with libcompat
          # supplying the headers illumos has and glibc does not.
          "COMPAT_CPPFLAGS=-I${libcompat}/include-native -I${libcompat}/include -include ${libcompat}/include-native/native_compat.h"

          "SGSMSG=${sgsmsg}/bin/sgsmsg"
          "CONVLIBDIR=-L${sgs-libconv}/lib"
          "CONVLIBDIR64=-L${sgs-libconv}/lib"
          "ELFLIBDIR=-L${sgs-libelf}/lib"
          "ELFLIBDIR64=-L${sgs-libelf}/lib"
          "LDLIBDIR=-L${sgs-libld}/lib"
          "LDLIBDIR64=-L${sgs-libld}/lib"
          "LDDBGLIBDIR=-L${sgs-liblddbg}/lib"
          "LDDBGLIBDIR64=-L${sgs-liblddbg}/lib"

          # libumem is illumos'; the host has none.
          "UMEMLIB="
          "COMPATLIB=-L${libcompat}/lib/i386 -lcompat"

          # cmd/sgs/ld/Makefile.com sets RPATH to Solaris' -R spelling, which the
          # GNU driver rejects outright. The native link needs no runpath of its
          # own: the support libraries are buildInputs, so the cc wrapper already
          # records their store paths.
          "RPATH="
        ];

    meta = {
      platforms = lib.platforms.unix;
      # The shipping ld(1) -- INCOMPLETE, and marked broken accordingly.
      #
      # Nothing we build consumes an illumos-hosted link-editor (everything uses
      # `buildPackages.illumos.ld`), so this branch exists to give the attribute
      # the right shape rather than because anything needs it yet. It gets as far
      # as generating msg.c with sgsmsg and compiling every object; what stops it
      # is the final executable link. cmd/Makefile.cmd:122 links programs through
      # the compiler driver, so the link runs GNU ld via collect2, which rejects
      # -Bdirect -- the same problem libm has, and it wants the same treatment:
      # override the link rule to invoke $(LD) directly. That plus running the
      # result (which needs an illumos host or emulator) is the remaining work.
      #
      # `meta.broken` rather than a plausible-looking derivation: a cross build of
      # this used to fail obscurely inside sgsmsg, and someone reaching for it
      # should get told it is unfinished, not debug it afresh.
      broken = forIllumos;
    };
  }
)
