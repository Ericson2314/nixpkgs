{
  stdenv,
  buildPackages,

  cw,
  ld,
  ld-wrapper,
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

# The build environment shared by every derivation that runs make inside
# usr/src/uts: `uts-base` (headers, assym.h, genunix, unix) and each of the
# per-module derivations `kmod.nix` produces.
#
# This is one attrset rather than duplicated boilerplate because the two must
# agree exactly. A module's CTF is uniquified against `uts-base`'s genunix
# (uts/Makefile.uts:320), so the two builds have to see the same compiler
# flags, the same $(LD) and the same BUILD_TYPE or the merge is comparing type
# graphs produced under different rules.
#
# The kernel needs no libc: `noLibc` keeps the cc-wrapper from adding
# `-isystem` paths into libc's headers, and uts/Makefile.uts:155 resets
# CPPFLAGS with `=` so that only the in-tree headers are searched.
{
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
    ld
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
    # The amd64 assembly for misc/md5 and misc/sha1 is *generated*, by the
    # OpenSSL-style perl scripts under $(SRC)/common/crypto (see
    # uts/intel/md5/Makefile:91, `md5_amd64.S: $(COMDIR)/amd64/md5_amd64.pl`).
    # Makefile.master:183 already says `PERL = perl`, so it only has to be on
    # $PATH. Without it dmake reports the far-from-obvious
    # "*** Error code 127 ... Command failed for target `md5_amd64.S'".
    buildPackages.perl
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
  #
  # Only `uts-base` runs genassym, but the macro expansion happens while
  # parsing Makefile.master in every uts make, so the module builds want the
  # same environment.
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  makeFlags = [
    # The one shared wrapper; see ld-wrapper.nix. It clears SGS_SUPPORT, which
    # dmake sets for .KEEP_STATE and which makes ld dlopen() a support library
    # with illumos-only mode flags. Its `-Wl,` splitting is a no-op here: the
    # uts makefiles invoke $(LD) directly rather than through a compiler
    # driver, so nothing arrives `-Wl,`-prefixed.
    #
    # A command-line macro is required rather than an environment variable:
    # uts/Makefile.uts:127 assigns LD = $(LD_$(MACH)_$(CLASS)), which would
    # otherwise win over the environment.
    "LD=${ld-wrapper}"

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
    # illumos' own strip preserves the layout, but it is mcs(1) from
    # cmd/sgs -- cross-built here, and absent from the tools/sgs NATIVE_BUILD
    # tree that gives us a build-machine `ld` -- so it cannot run on the build
    # machine at all. Skip the step, exactly as upstream does for source-debug
    # builds (Makefile.master:980). DWARF is removed later, by the
    # layout-preserving strip-dwarf.py in postFixup below.
    "STRIP_STABS=:"

    "NM=${buildPackages.writeShellScript "illumos-nm" ''
      exec ${stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}nm --format=posix "$@"
    ''}"
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

  # These are relocatable kmods for a foreign OS; none of the usual fixup
  # applies and RPATH shrinking would only confuse matters.
  dontStrip = true;
  dontPatchELF = true;

  # Split DWARF out of every kernel object into a `debug` output, the way
  # nixpkgs' separateDebugInfo does: the full debug info stays in the store
  # under $debug/lib/debug/<same path>, and $out keeps only what the running
  # kernel needs. Both `uts-base` and every `kmod` derivation get this; each
  # declares the extra output itself.
  #
  # This is the single biggest lever on boot time. GRUB copies the whole boot
  # archive into RAM before the kernel starts, and a DBG64 tree is ~125M of
  # which the overwhelming majority is DWARF -- genunix alone is 81M of it.
  #
  # The $out side is done by strip-dwarf.py, not by objcopy. That is not a
  # preference: GNU objcopy silently destroys these files in two ways that
  # cannot be repaired afterwards -- it truncates .strtab, taking a module's
  # DT_NEEDED dependency names with it, and it reorders unix's allocatable
  # sections so that the multiboot header leaves the first 8K. Both are
  # measured and written up at the top of that script. objcopy is still used
  # for $debug, which is a fresh file that nothing loads.
  #
  # strip-dwarf.py keeps every surviving section byte-identical, keeps every
  # section index, and never moves anything a program header covers, verifying
  # all of that plus the multiboot header and .SUNW_ctf before it replaces the
  # file. That is what makes it safe on `unix`, which objcopy is not -- see the
  # STRIP_STABS note above for that history.
  postFixup = ''
    objcopy=${stdenv.cc.bintools.bintools}/bin/${stdenv.cc.targetPrefix}objcopy
    stripDwarf="${buildPackages.python3Minimal}/bin/python3 ${./strip-dwarf.py}"

    mkdir -p "$debug"

  ''
  # A module installed under two names is one file with two links, not two
  # files: uts/intel/ip/Makefile:119 is `ln $(ROOTMODULE) $@`, so the 25M ip
  # is both kernel/drv/amd64/ip and kernel/strmod/amd64/ip, and nfs does the
  # same across kernel/fs and kernel/sys. strip-dwarf.py writes a temp file
  # and renames over the original, which breaks the link, so remember each
  # inode and re-link the second name onto the first result rather than
  # stripping the same bytes twice into two independent copies.
  + ''
    declare -A splitDebugSeen=()

    while IFS= read -r -d "" f; do
      [ "$(head -c 4 "$f" | tr -d '\0')" = $'\177ELF' ] || continue

  ''
  # `ls -di` rather than `stat`, to keep a literal percent sign out of
  # this script entirely. nix-shell renders the derivation environment
  # through boost::format, which reads a percent-i as a format specifier
  # and dies with
  #
  #     boost::bad_format_string: format-string is ill-formed
  #
  # BEFORE running anything -- so `nix-shell -A ...unix.kmods.<mod>`, the
  # documented fast loop for kernel-module work, breaks outright, even
  # though that loop drives `make` by hand and never reaches a fixup
  # phase. Respelling the flag does not help: the percent is the problem.
  + ''
      ino=$(ls -di "$f" | awk '{print $1}')
      if [ -n "''${splitDebugSeen[$ino]:-}" ]; then
        ln -f "''${splitDebugSeen[$ino]}" "$f"
        continue
      fi

      # --only-keep-debug reads the file as it stands, so it has to come first.
      dbg="$debug/lib/debug/''${f#$out/}.debug"
      mkdir -p "$(dirname "$dbg")"
      "$objcopy" --only-keep-debug "$f" "$dbg"

      $stripDwarf "$f"
      splitDebugSeen[$ino]="$f"
    done < <(find "$out" -type f -print0)
  '';
}
