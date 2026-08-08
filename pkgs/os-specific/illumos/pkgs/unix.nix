{
  lib,
  stdenv,
  mkDerivation,
  buildPackages,

  illumosSetupHook,
  make,
  install,
  cw,
  ld-native,
  ctfconvert,
  ctfmerge,
  ctfstabs,
  genoffsets,
  nawk,
  rpcgen,
  elfextract,
  mbh-patch,
  vtfontcvt,
}:

# The i86pc kernel: `genunix` (plus the `libgenunix.so` stub library that
# everything else links against) and `unix` itself.
#
# uts is built out of one source tree rather than one derivation per module.
# The module Makefiles reach into each other's object directories by relative
# path -- uts/i86pc/unix/Makefile:52 links against
# `../../intel/genunix/$(OBJS_DIR)` -- so splitting them up would mean
# reassembling that layout anyway.
#
# The kernel needs no libc: `noLibc` keeps the cc-wrapper from adding
# `-isystem` paths into libc's headers, and uts/Makefile.uts:155 resets
# CPPFLAGS with `=` so that only the in-tree headers are searched.
mkDerivation {
  pname = "unix";
  noLibc = true;

  path = "usr/src/uts";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"
    "usr/src/Makefile.psm"
    "usr/src/Makefile.psm.targ"

    # uts/common/Makefile.rules compiles a good deal of $(SRC)/common into the
    # kernel: atomic, util, font, fs, dis and so on.
    "usr/src/common"
    # ...and the bundled zlib, via $(SRC)/contrib/zlib.
    "usr/src/contrib/zlib"
    # The BDF console font behind FONT_OBJS (uts/common/Makefile.files:1684),
    # which is part of CORE_OBJS and so of unix proper.
    "usr/src/data/consfonts"
  ];

  extraNativeBuildInputs = [
    cw
    # $(LD) is illumos' own: the kernel mapfiles are `$mapfile_version 2` and
    # the module link needs -ztype=kmod, neither of which GNU ld has.
    ld-native
    # Every object gets a CTF section, and genunix is the uniquification
    # source for the rest of the kernel.
    ctfconvert
    ctfmerge
    ctfstabs
    # $(OFFSETS_CREATE), used by uts/i86pc/genassym to turn ml/offsets.in into
    # assym.h.
    genoffsets
    # $(AWK) is nawk, not gawk; the dtracestubs rule in
    # uts/i86pc/Makefile.rules:325 relies on it.
    nawk
    # uts/common/rpc and uts/common/nfs generate headers with rpcgen.
    rpcgen
    # The three onbld tools the unix build shells out to: the multiboot-header
    # patcher, the dboot embedder, and the console-font converter.
    mbh-patch
    elfextract
    vtfontcvt
    # illumos' own arch(1)/mach(1) report "i386" on x86, not "x86_64".
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ];

  # uts/i86pc/genassym builds a program with $(NATIVECC) and then *runs* it to
  # emit part of assym.h. That needs a compiler for the build machine, which is
  # what puts $CC_FOR_BUILD in the environment for Makefile.master's NATIVE*
  # macros. (The struct offsets in assym.h do not come from there: those are
  # $(OFFSETS_CREATE)'s doing, reading the target compiler's CTF.)
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  makeFlags = [
    # illumos' MACH/MACH64 are not uname processor strings: on x86 they are
    # "i386" and "amd64". Getting this wrong silently empties file lists and
    # sends source lookups into directories that do not exist.
    "MACH=i386"
    "MACH64=amd64"


    # See the LD note in libcMinimal.nix. Two things are going on: this must
    # name the *build platform* link-editor explicitly (splicing does not
    # rewrite string interpolation), and it must be wrapped to clear
    # SGS_SUPPORT, which dmake sets for .KEEP_STATE and which makes ld
    # dlopen() a support library with illumos-only mode flags.
    #
    # A command-line macro is required rather than an environment variable:
    # uts/Makefile.uts:127 assigns LD = $(LD_$(MACH)_$(CLASS)), which would
    # otherwise win over the environment.
    "LD=${
      buildPackages.writeShellScript "illumos-ld" ''
        unset SGS_SUPPORT SGS_SUPPORT_32 SGS_SUPPORT_64
        exec ${buildPackages.illumos.ld-native}/bin/ld "$@"
      ''
    }"

    # uts/i86pc/Makefile.rules:326 feeds `$(NM) -u` into awk and takes the
    # symbol name from $1. GNU nm's default format puts the symbol last
    # ("                 U foo"); its POSIX format puts it first ("foo U"),
    # which is what the rule expects.
    # Makefile.master:124 looks these up under $(ONBLD_TOOLS)/bin/$(MACH), an
    # installed onbld proto area that does not exist here. Each is its own
    # derivation and lands on $PATH instead.
    "ELFEXTRACT=elfextract"
    "MBH_PATCH=mbh_patch"
    "VTFONTCVT=vtfontcvt"

    # Makefile.master:989 ends every link with $(POST_PROCESS), whose
    # $(STRIP_STABS) is `$(STRIP) -x $@`. $(STRIP) is not set by the makefiles
    # (Makefile.master:162 has it commented out), so it comes from the
    # environment -- GNU strip from the cross toolchain.
    #
    # GNU strip rewrites the file rather than editing it in place, and lays
    # allocatable sections out in *signed* address order. unix has its 1:1
    # mapped dboot segment at 0xc00000 and everything else at
    # 0xfffffffffb800000, so dboot -- which the link and mbh_patch had both put
    # first, at file offset 0x158 -- ends up last, at 0x1de728. That moves the
    # multiboot header out of the first 8K (MB1) / 32K (MB2) of the file where
    # every boot loader looks for it, and invalidates the load_addr and
    # header_addr mbh_patch had already computed from the old offset. The
    # result is an ELF whose contents are correct but which no loader will
    # recognise as bootable.
    #
    # illumos' own strip preserves the layout; nothing here needs stripping
    # anyway (see dontStrip below), so skip the step, exactly as upstream does
    # for source-debug builds (Makefile.master:980).
    "STRIP_STABS=:"

    "NM=${
      buildPackages.writeShellScript "illumos-nm" ''
        exec ${stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}nm --format=posix "$@"
      ''
    }"
  ];

  # genassym.c reaches <sys/cmn_err.h>, whose __KPRINTFLIKE expands to
  # __attribute__((format(cmn_err, ...))). That format archetype exists only in
  # illumos' GCC fork, which here is the *target* compiler; the build-host
  # compiler is stock GCC and rejects it under -Werror=format.
  #
  # This goes through the cc-wrapper rather than CUSERFLAGS because dmake does
  # not survive passing a command-line macro whose value itself contains an '='
  # ("-_gcc=-Wno-format") down to the recursive $(MAKE) that Makefile.targ:263
  # spawns for the build type.
  #
  # -m64: NATIVE_MACH is $(MACH:amd64=i386), i.e. i386, so NATIVE_CFLAGS
  # carries -m32 (Makefile.master:736, :468) and the build host would need a
  # 32-bit glibc to link uts/i86pc/genassym. genassym prints only preprocessor
  # constants -- ml/genassym.c even `#define`s `struct` to a syntax error to
  # keep anyone from reaching for a struct offset -- so the data model does not
  # matter. This has to travel through the cc-wrapper rather than a
  # NATIVE_MACH= macro: both unix and genunix reach assym.h through an FRC rule
  # that re-enters uts/i86pc/genassym with a bare `$(MAKE) all.targ`
  # (uts/i86pc/unix/Makefile:199), and dmake carries MACH across that but not
  # NATIVE_MACH -- so genassym would be rebuilt there, -m32, and fail. The
  # wrapper appends these last, after the -m32.
  NIX_CFLAGS_COMPILE_FOR_BUILD = "-Wno-format -m64";

  # NetBSD's rpcgen shells out to a C preprocessor, defaulting to a /usr/bin
  # path that does not exist here. It then emits only boilerplate and still
  # exits 0, so the generated headers come out nearly empty and the failure
  # surfaces much later as a missing type -- here rpc/rpc_sztypes.h not
  # defining `uint32`, which rpc/rpc_rdma.h then uses. It also has to be a
  # *traditional* cpp; see the identical note in uts-headers.nix.
  env.RPCGEN_CPP = buildPackages.writeShellScript "rpcgen-cpp" ''
    exec ${buildPackages.stdenv.cc}/bin/cpp -traditional-cpp -U__STDC__ "$@"
  '';

  # hardeningDisable below only stops the cc-wrapper from *adding* -fPIE; it
  # does not undo a GCC configured --enable-default-pie, which this one is. The
  # kernel is compiled -mcmodel=kernel (cw's translation of -xmodel=kernel) and
  # "code model kernel does not support PIC mode", so say so explicitly.
  #
  # --param=min-pagesize=0: i86pc/io/pci/pci_prd_i86pc.c's mps_probe() reads the
  # BIOS data area through absolute pointers (`*((ushort_t *)(0x413))`), which
  # GCC >= 14 flags as -Warray-bounds "outside array bounds ... likely at
  # address zero". uts/i86pc/Makefile.rules already passes exactly this to
  # silence it, but as `-_gcc14=--param=min-pagesize=0`, and cw only forwards
  # those to the compiler it was told is primary -- which the illumos stdenv
  # declares as `gcc10`, so a GCC 14 cross compiler never sees them.
  NIX_CFLAGS_COMPILE = "-fno-pie --param=min-pagesize=0";

  # None of nixpkgs' default hardening applies to a kernel, and `pie` actively
  # breaks it: the cc-wrapper's -fPIE is incompatible with the -mcmodel=kernel
  # that cw derives from -xmodel=kernel ("code model kernel does not support
  # PIC mode"). _FORTIFY_SOURCE and the stack protector would want libc
  # runtime support that does not exist in the kernel either.
  hardeningDisable = [ "all" ];

  # There is no `configure` anywhere under uts.
  dontConfigure = true;

  # illumosSetupHook probes for an `install_h` target before installing. uts has
  # one, but it is the whole kernel header set -- that is uts-headers' job, not
  # this derivation's -- and merely probing for it makes dmake parse
  # uts/Makefile, which includes a ../Makefile.xref we do not stage.
  skipIncludesPhase = true;

  buildPhase = ''
    runHook preBuild

    local flagsArray=()
    concatTo flagsArray makeFlags makeFlagsArray

    # `def.targ` rather than `def`: `def` expands to $(DEF_DEPS), whose rule
    # (uts/Makefile.targ:263) re-invokes $(MAKE) with BUILD_TYPE set, and dmake
    # does not carry every command-line macro across that extra level -- MACH
    # survives, NATIVE_MACH does not. Setting BUILD_TYPE ourselves and asking
    # for the inner target keeps everything at one make level. DBG64 is what
    # DEF_BUILDS64 selects for a non-release build (uts/Makefile.uts:69).
    export BUILD_TYPE=DBG64

    # Several header directories under uts/common have generated members:
    # sys/priv_names.h and friends come from awk (uts/common/sys/Makefile:1386),
    # rpc/rpc_sztypes.h and friends from rpcgen (uts/common/rpc/Makefile:110).
    # A real build has them installed into /usr/include long before the kernel
    # is compiled; here the kernel reads them straight out of the tree. `all_h`
    # is exactly the generated set and installs nothing.
    for mk in common/*/Makefile; do
      grep -q '^all_h:' "$mk" || continue
      ( cd "$(dirname "$mk")" && make "''${flagsArray[@]}" all_h )
    done

    # assym.h and kdi_assym.h, consumed by the assembly in both unix and
    # genunix.
    ( cd i86pc/genassym && make "''${flagsArray[@]}" def.targ )

    # Both genunix and unix depend on assym.h through an FRC rule that
    # unconditionally re-enters this directory with a bare `$(MAKE) all.targ`
    # (uts/i86pc/unix/Makefile:199). That nested make does not see our
    # command-line macros -- dmake only hands down macros that came from the
    # environment, and Makefile.master/Makefile.uts reassign the rest -- and,
    # worse, it inherits CC as the whole expanded `cw --tag target ...` command
    # line, so Makefile.master's `PRIMARY_CC_PATH:sh = command -v $CC`
    # resolves to cw and cw is then handed itself as the primary compiler.
    #
    # dmake's .KEEP_STATE notices the changed command line and rebuilds, which
    # is what makes any of that visible. The headers are already correct at
    # this point and nothing regenerates them, so retire the Makefile that
    # would rebuild them; the directory stays where it is, so
    # -I$(DSF_DIR)/$(OBJS_DIR) still finds them.
    cat > i86pc/genassym/Makefile <<'EOF'
    # Replaced by nixpkgs' pkgs/os-specific/illumos/pkgs/unix.nix. The real
    # Makefile has already run; these targets exist only so that the FRC rules
    # in unix and genunix find the generated headers up to date.
    all.targ def.targ all def install clean clobber:
    EOF
    sed -i 's/^    //' i86pc/genassym/Makefile

    # common/os/priv_const.c is generated from the same awk script and table.
    # uts/intel/Makefile:73 owns the rule and hangs it off a `genunix` target;
    # upstream reaches it through uts/Makefile's `.prereq` machinery, which is
    # part of the parallel-build scaffolding we are not using.
    # Ask for the file, not for uts/intel/Makefile's `genunix:` target: genunix
    # is also a $(KMODS) entry there, so the name matches a second rule that
    # recurses into intel/genunix -- and that recursion re-exports CC as the
    # whole `cw ...` command line, which the next level's `command -v $CC` then
    # resolves to cw itself.
    ( cd intel && make "''${flagsArray[@]}" "$SRC/uts/common/os/priv_const.c" )

    # genunix first: uts/i86pc/unix/Makefile:52 links unix against
    # ../../intel/genunix/$(OBJS_DIR)/libgenunix.so.
    #
    # IPCTF_TARGET= drops the ipctf.a step (uts/Makefile.uts:337): genunix
    # normally has the whole ip driver's CTF merged into it so that networking
    # types are available to uniquify other modules against. That is a
    # size/space optimisation for the rest of the kernel, not something genunix
    # or unix needs to link, and building it would drag in all of intel/ip.
    ( cd intel/genunix && make "''${flagsArray[@]}" IPCTF_TARGET= def.targ )

    ( cd i86pc/unix && make "''${flagsArray[@]}" def.targ )

    runHook postBuild
  '';

  # The loadable modules startup_modules() and vfs_mountroot() reach for, in
  # dependency order. Each entry is a directory under uts; the module's own
  # Makefile knows its class, so `install.targ` puts it in the right place
  # under $(ROOT) -- kernel/fs/amd64/specfs,
  # platform/i86pc/kernel/drv/amd64/rootnex, and so on.
  kmods = [
    # startup.c:1515 onwards halts if any of these four are missing. specfs
    # links -Nfs/fifofs, so fifofs has to exist first.
    #
    # The -N entries in each module's LDFLAGS are hard dependencies that krtld
    # resolves at modload() time, so they have to be here too: specfs needs
    # fs/fifofs, procfs needs fs/namefs, and fs/dev needs misc/dls, which in
    # turn needs misc/mac.
    "intel/fifofs"
    "intel/specfs"
    "intel/devfs"
    "intel/mac"
    "intel/dls"
    "intel/dev"
    "intel/namefs"
    "intel/procfs"

    # setup_ddi() roots the device tree at rootnex. rootnex links
    # -N misc/iommulib -N misc/acpica, so both have to be loadable too.
    "intel/acpica"
    "intel/iommulib"
    "i86pc/rootnex"

    # impl_setup_ddi() (i86pc/os/ddi_impl.c:2610) creates a "ramdisk" devinfo
    # node for the boot archive and ASSERTs that ndi_devi_bind_driver()
    # succeeds. The assertion is unconditional in a DEBUG kernel, so drv/ramdisk
    # is a hard requirement, not a convenience.
    "intel/ramdisk"

    # impl_bus_initialprobe() (i86pc/os/ddi_impl.c) panics unless
    # misc/pci_autoconfig and drv/isa load, and modloads misc/acpidev on the
    # way. pci_autoconfig needs misc/pcie and misc/pci_prd; pcie needs
    # misc/busra; isa needs all three.
    "intel/busra"
    "i86pc/pci_prd"
    "i86pc/pcie"
    "intel/pci_autoconfig"
    "i86pc/acpidev"
    "i86pc/isa"

    # i_ddi_init_root() (common/os/autoconf.c:462) attaches the "options" and
    # "pseudo" nodes by name and then enumerates pseudo's .conf children. With
    # no drv/pseudo the attach returns NULL and i_ndi_make_spec_children()
    # asserts on it; the giveaway earlier in the log is "add_spec: No major
    # number for pseudo".
    "intel/options"
    "intel/pseudo"

    # dispinit() instantiates the scheduling classes named in
    # common/disp/disp.c's class table; TS is the default one and pulls in its
    # dispatch-parameter table, and SDC is what the kernel's own taskq threads
    # run under.
    "intel/TS"
    "intel/TS_DPTBL"
    "intel/SDC"

    # psm_modload() (startup.c:1649) loads every module under
    # platform/i86pc/kernel/mach; uppc is the plain 8259/8254 one that works
    # without an APIC.
    "i86pc/uppc"

    # main() calls vfs_mountroot() almost immediately after startup, and
    # rootconf() (common/fs/vfs.c:4512) panics unless it can modload the root
    # filesystem named by the "fstype" boot property -- "ufs" by default.
    # ufs links -Nfs/specfs -Nmisc/fssnap_if.
    "intel/fssnap_if"
    "intel/ufs"
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/platform/i86pc/kernel/amd64" "$out/kernel/amd64" "$out/lib"
    cp i86pc/unix/debug64/unix "$out/platform/i86pc/kernel/amd64/unix"
    cp intel/genunix/debug64/genunix "$out/kernel/amd64/genunix"
    cp intel/genunix/debug64/libgenunix.so "$out/lib/libgenunix.so"

    # The identity-mapped entry stub. It is already embedded in `unix` -- the
    # link uses `-e dboot_image`, and uts/i86pc/unix/Makefile:181 turns it into
    # an object with elfextract -- but it is useful to have on its own.
    cp i86pc/unix/dboot/debug64/dboot "$out/platform/i86pc/kernel/amd64/dboot"

    # The rest of the modules. `install.targ` rather than `install`: same
    # BUILD_TYPE recursion problem as `def` above. ROOT is prepended as empty
    # by illumosSetupHook's addIllumosMakeFlags, so it has to be re-set here,
    # after flagsArray, to win.
    local flagsArray=()
    concatTo flagsArray makeFlags makeFlagsArray
    export BUILD_TYPE=DBG64

    # $(INS) is `install`, which resolves to $(ONBLD)/install.bin -- and the
    # `install` derivation is *cross*-built, so on the build machine the shell
    # falls through to coreutils' install, which has neither -f nor a
    # -s-with-a-directory. Nothing here needs install(1)'s semantics: these are
    # plain file copies into $out. Note the escaped `$`: make, not the shell,
    # has to expand $@/$</$(@D).
    flagsArray+=(
      "INS.dir=mkdir -p \$@"
      "INS.file=mkdir -p \$(@D); rm -f \$@; cp \$< \$@"
      "INS.conffile=mkdir -p \$(@D); rm -f \$@; cp \$(SRC_CONFFILE) \$@"
    )

    for m in $kmods; do
      ( cd "$m" && make "''${flagsArray[@]}" IPCTF_TARGET= "ROOT=$out" install.targ )
    done

    runHook postInstall
  '';

  # `unix` and `genunix` are relocatable kmods for a foreign OS; none of the
  # usual fixup applies and RPATH shrinking would only confuse matters.
  dontStrip = true;
  dontPatchELF = true;
}
