{
  lib,
  stdenv,
  stdenvNoCC,
  stdenvNoLibc,
  stdenvLibcMinimal,
  filterSource,
  filterPatches,
  patchesRoot,
  illumosSetupHook,
  make,
  install,
  version,

  # Only forced by packages that opt into `illumosLib` below, so the bootstrap
  # packages that build *these* (headers, cw, ld) can keep using mkDerivation
  # without tying the knot.
  buildPackages,
  cw,
  ld-wrapper,
  headers,
}:

let
  # illumos' own arch(1)/mach(1) report "i386" on x86, not "x86_64", and the
  # lib makefiles shell out to them.
  archStubs = [
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ];

  # The makefile fragments read by every usr/src/lib/* build before it reaches
  # its own Makefile.
  libMakefilePaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
  ];

  # Makefile.master:983 leaves POST_PROCESS_O empty and Makefile.lib:191
  # appends "; $(CTFCONVERT_POST)" to it, so the expanded recipe line starts
  # with a bare `;`, which the shell rejects. Both settings below cure that;
  # the difference is only whether CTF is actually produced.
  #
  # Under `illumosCtf` the macro is restated as just the hook. It has to stay a
  # *reference* rather than being resolved here, because CTFCONVERT_POST is
  # target-conditional -- Makefile.lib:208 sets it to $(CTFCONVERT_O) for
  # $(PICS) and leaves it `:` elsewhere -- so it must expand in each target's
  # own context.
  ctfMakeFlags = [
    "POST_PROCESS_O=$(CTFCONVERT_POST)"
    "POST_PROCESS_SO=$(CTFMERGE_POST)"
  ];

  noCtfMakeFlags = [
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"
  ];

  libMakeFlags = [
    # The libc_pic.a rule runs `mcs -d -n .SUNW_ctf` to drop the per-object CTF
    # from the archive, since only the shared library is meant to carry it. mcs
    # is an illumos *target* program (cmd/sgs/mcs) with no build-host build, so
    # the step is skipped: the archive keeps a .SUNW_ctf in each member, which
    # costs some space and changes nothing about linking.
    "MCS=:"
    # LDFLAGS.native is $(LDASSERTS) $(BDIRECT) -- Solaris ld options, which
    # GNU ld rejects when linking a native helper program (libc's genassym).
    # Clear just that, not BDIRECT itself: DYNFLAGS also uses $(BDIRECT), and
    # the shared-library links run under illumos ld with -zguidance
    # -zfatal-warnings, which turns a missing -Bdirect into a hard error.
    "LDFLAGS.native="
    # The installed headers must be searched *before* the -I flags individual
    # rules add, not after. Makefile.targ's regex rule adds
    # -I$(LIBCBASE)/../port/regex, and libc keeps a private regex.h there which
    # does not define REG_ESPACE and friends; a native build gets the public
    # <regex.h> first because $(COMPILE.c) already carries -I$(SRC)/head.
    # Arriving via -isystem (as buildInputs do) is too late in the search
    # order. CPPFLAGS.first is placed ahead of everything else in CPPFLAGS.
    "CPPFLAGS.first=-I${headers}/include"
    # illumos' MACH/MACH64 are not uname processor strings: on x86 they are
    # "i386" and "amd64". Source lookups depend on this -- Makefile.targ finds
    # the complex-arithmetic sources via $(LIBCBASE)/../$(MACH)/fp/%.c, which
    # is lib/libc/i386/fp. Passing MACH=x86_64 sends it to a directory that
    # does not exist.
    #
    # TARGET_ARCH is deliberately not overridden: the amd64 makefiles set it
    # themselves, and a command-line macro would clobber that.
    "MACH=i386"
    "MACH64=amd64"
  ];
in

lib.makeOverridable (
  attrs:
  let
    stdenv' =
      if attrs.noCC or false then
        stdenvNoCC
      else if attrs.noLibc or false then
        stdenvNoLibc
      else if attrs.libcMinimal or false then
        stdenvLibcMinimal
      else
        stdenv;

    pname = attrs.pname or (baseNameOf attrs.path);

    # `illumosLib`: opt in to the shared boilerplate for a usr/src/lib/*
    # library -- the common makefile fragments, tools and command-line macros
    # defined above. Deliberately opt-in rather than automatic: the remaining
    # per-library variation (BUILD.SO overrides, STACKPROTECT) is load-bearing
    # and stays in the individual packages.
    isLib = attrs.illumosLib or false;

    # Link through illumos' own link-editor. On by default for `illumosLib`;
    # a static-only library (libssp_ns) never links anything and turns it off.
    #
    # This adds only the `LD=` macro, not a `nativeBuildInputs` entry. `ld`
    # used to be in both; dropping the PATH entry was verified to leave
    # libc.so.1, libm.so.2, libpthread.so.1 and libc_pic.a bit-identical,
    # because `LD=` names the wrapper by absolute path and nothing here ever
    # resolves a bare `ld` off PATH. Note the consequence: the only `ld` on
    # PATH is the cross binutils one, so a makefile that did start calling
    # `ld` unqualified would get GNU ld rather than illumos'.
    useLd = attrs.illumosLd or isLib;

    # Produce real CTF rather than stubbing the post-processing out. Opt-in:
    # it needs ctfconvert/ctfmerge on the build host and DWARF in the objects.
    enableCtf = attrs.illumosCtf or false;

    extraPaths = lib.optionals isLib libMakefilePaths ++ attrs.extraPaths or [ ];
    paths = [ attrs.path ] ++ extraPaths;
  in
  stdenv'.mkDerivation (
    {
      pname = "${pname}-illumos";
      inherit version;

      src = filterSource {
        inherit pname extraPaths;
        inherit (attrs) path;
      };

      inherit extraPaths;

      # Pick out just the hunks of the shared patch set that touch this
      # package's own subset of the tree, so that editing an unrelated hunk does
      # not rebuild this package. Set `autoPickPatches = false` to opt out.
      patches =
        lib.optionals (attrs.autoPickPatches or true) (filterPatches { } patchesRoot paths)
        ++ attrs.patches or [ ];

      nativeBuildInputs = [
        illumosSetupHook
        make
        install
      ]
      ++ lib.optionals isLib ([ cw ] ++ archStubs)
      ++ (attrs.extraNativeBuildInputs or [ ]);

      COMPONENT_PATH = attrs.path or null;

      strictDeps = true;

      meta = with lib; {
        maintainers = with maintainers; [ ericson2314 ];
        platforms = platforms.illumos;
        license = licenses.cddl;
      };
    }
    // lib.optionalAttrs (attrs.headersOnly or false) {
      installPhase = "includesPhase";
      dontBuild = true;
    }
    // (builtins.removeAttrs attrs [
      "extraNativeBuildInputs"
      "autoPickPatches"
      "patches"
      "extraPaths"
      "illumosLib"
      "illumosLd"
      "illumosCtf"
    ])
    # Last, so that these are *prepended* to whatever the package asked for
    # rather than replaced by it. Only set when opted in: unconditionally
    # defining `makeFlags` would add the (empty) variable to every illumos
    # derivation and change all their hashes.
    // lib.optionalAttrs isLib {
      makeFlags =
        libMakeFlags
        ++ (if enableCtf then ctfMakeFlags else noCtfMakeFlags)
        ++ lib.optional useLd "LD=${ld-wrapper}"
        ++ attrs.makeFlags or [ ];
    }
  )
)
