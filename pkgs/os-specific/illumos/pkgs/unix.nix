{
  lib,
  stdenv,
  mkDerivation,
  buildPackages,

  illumosSetupHook,
  make,
  install,
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
  depsBuildBuild = [ buildPackages.stdenv.cc ];

  makeFlags = [
    # illumos' MACH/MACH64 are not uname processor strings: on x86 they are
    # "i386" and "amd64". Getting this wrong silently empties file lists and
    # sends source lookups into directories that do not exist.
    "MACH=i386"
    "MACH64=amd64"

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
    # illumos' own strip preserves the layout; nothing here needs stripping
    # anyway (see dontStrip below), so skip the step, exactly as upstream does
    # for source-debug builds (Makefile.master:980).
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

    # common/os/priv_const.c is generated from the same awk script and table.
    # uts/intel/Makefile:73 owns the rule and hangs it off a `genunix` target;
    # upstream reaches it through uts/Makefile's `.prereq` machinery, which is
    # part of the parallel-build scaffolding we are not using.
    # Ask for the file, not for uts/intel/Makefile's `genunix:` target: genunix
    # is also a $(KMODS) entry there, so the name matches a second rule that
    # recurses into intel/genunix and rebuilds the whole module.
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

    # pipe(2) is a *loadable* syscall: common/os/sysent.c:488 is
    # `/* 42 */ SYSENT_LOADABLE(), /* pipe */`, and the implementation ships as
    # its own module (SYS_KMODS in intel/Makefile.intel, source in intel/pipe),
    # installed to kernel/sys/$(MACH64). Without it slot 42 stays nosys(), so
    # the first shell pipeline kills the process running it:
    #
    #     -bash: pipe error: Operation not applicable
    #     WARNING: init(8) exited on fatal signal 12
    #
    # -- signal 12 being SIGSYS and errno 89 ENOSYS, which reads like a
    # filesystem or STREAMS problem and is neither.
    "intel/pipe"

    # The other loadable-syscall modules userland actually reaches for.
    # `sysent.c` has 17 `SYSENT_LOADABLE()` slots and each one is a `nosys()`
    # -- i.e. a SIGSYS -- until its module is present, so they are worth
    # shipping ahead of the failure rather than one panic at a time:
    #
    #   doorfs   door_call(3C). libscf talks to svc.configd over a door, and
    #            so does the name-service cache, so SMF needs this.
    #   portfs   event ports (port_create(3C)), the illumos poll replacement.
    #   shmsys   } System V IPC. Plenty of ported software probes for these
    #   semsys   } and quietly takes a worse path when they are missing,
    #   msgsys   } rather than failing loudly.
    "intel/doorfs"
    "intel/portfs"
    "intel/shmsys"
    "intel/semsys"
    "intel/msgsys"

    # main() calls vfs_mountroot() almost immediately after startup, and
    # rootconf() (common/fs/vfs.c:4512) panics unless it can modload the root
    # filesystem named by the "fstype" boot property -- "ufs" by default.
    # ufs links -Nfs/specfs -Nmisc/fssnap_if.
    "intel/fssnap_if"
    "intel/ufs"

    # ...and hsfs, which is what we actually root on. The boot archive reaches
    # the kernel as a ramdisk whose block device (/ramdisk:a) is the loaded
    # module byte for byte -- impl_setup_ddi() (i86pc/os/ddi_impl.c) just hands
    # ramdisk_start/ramdisk_end to drv/ramdisk as its "existing" property, and
    # nothing anywhere unpacks anything. So the archive has to *be* a
    # filesystem image. Of the formats bootadm(8) knows (bam_formats[] in
    # cmd/boot/bootadm/bootadm.c: hsfs, ufs, cpio, ufs-nocompress), hsfs is the
    # only one we can produce here: mkfs_ufs is a target program that cannot
    # run on the Linux build host, and cpio is readable only by krtld's
    # bcpio_ops -- there is no cpio entry in common/os/vfs_conf.c, so a cpio
    # archive can never be a root filesystem.
    #
    # hsfs_mountroot() (common/fs/hsfs/hsfs_vfsops.c:1457) takes its device
    # from plain getrootdev(), with nothing CD-specific about it, so rooting on
    # an iso9660 image in the ramdisk needs no disk driver stack at all. The
    # standalone reader krtld uses before the root mount is already linked into
    # unix (hsfs.o is in KRTLD_OBJS, uts/intel/Makefile.files:172, and
    # bhsfs_ops is in bfs_tab[] in common/krtld/bootrd.c).
    #
    # hsfs links -Nfs/specfs, which is already above.
    "intel/hsfs"

    # vfs_mountroot() does not stop at the root: it goes on to mount the
    # kernel's own synthetic filesystems (common/fs/vfs.c vfs_mountroot ->
    # vfs_mountdevices/vfs_mountfs). Each missing one is only a WARNING, but
    # they are cheap and everything above init expects them:
    #   ctfs    /system/contract
    #   objfs   /system/object
    #   bootfs  /system/boot
    #   mntfs   /etc/mnttab
    #   sharefs /etc/dfs/sharetab
    #   tmpfs   /etc/svc/volatile
    "intel/ctfs"
    "intel/objfs"
    "intel/bootfs"
    "intel/mntfs"
    "intel/sharefs"
    "intel/tmpfs"

    # Sockets. `socket(2)` itself is not in genunix: the whole family lives in
    # fs/sockfs (common/fs/sockfs/socksyscalls.c), and AF_UNIX is implemented
    # there too (sockcommon_sops.c, sockcommon_vnops.c). Without this module
    # there are no sockets of any kind in userland, unix-domain included --
    # which is what SMF's socket plumbing and nix-daemon both need.
    #
    # sockfs is a filesystem module, but it is not free-standing: its Makefile
    # (uts/intel/sockfs/Makefile) has `LDFLAGS += -Ndrv/ip`, and krtld resolves
    # -N at modload() time whether or not there is a NIC. So the IP stack has
    # to come with it.
    #
    #   ip     -Nmisc/md5 -Ncrypto/swrand -Nmisc/hook -Nmisc/neti
    #          -Nmisc/cc -Ncc/cc_{sunreno,newreno,cubic}
    #   md5    -Nmisc/kcf          (the kernel crypto framework)
    #   swrand -Nmisc/kcf -Nmisc/sha1
    #   sha1   -Nmisc/kcf
    #   neti   -Nmisc/hook
    #
    # misc/mac and misc/dls are already above -- fs/dev needs them.
    "intel/kcf"
    "intel/md5"
    "intel/sha1"
    "intel/swrand"
    "intel/hook"
    "intel/neti"
    "intel/cc"
    "intel/cc_sunreno"
    "intel/cc_newreno"
    "intel/cc_cubic"
    "intel/ip"
    "intel/sockfs"

    # AF_UNIX is *not* self-contained in sockfs. sockfs implements the socket
    # layer, but the unix-domain transport underneath it is TPI: soconfig(8)'s
    # table (cmd/cmd-inet/etc/sock2path.d/system%2Fkernel) maps family 1 onto
    # the device paths /dev/ticotsord and /dev/ticlts, which are minor nodes of
    # drv/tl, the transport-loopback driver (uts/common/io/tl.c:524 onwards).
    # No tl, no unix-domain sockets. tl also links -Ndrv/ip.
    "intel/tl"

    # AF_ROUTE (family 24, `rts`). ifconfig/route/ipadm all talk to the kernel
    # routing table through a PF_ROUTE socket, so this is not optional once
    # there is any network configuration to do.
    "intel/rts"

    # The STREAMS modules a TPI transport gets pushed. timod turns a stream
    # into a TLI/XTI endpoint, which is what libnsl's t_open(3NSL) -- and so
    # the RPC/`netconfig` path -- expects; strplumb() modloads it by name.
    "intel/timod"
    "intel/tirdwr"

    # The MAC-type plugins. misc/mac has no Ethernet knowledge of its own:
    # mac_init_ops() looks the plugin up by media type at driver registration
    # (common/io/mac/mac_provider.c -> mactype_getplugin("mac_ether")), so a
    # NIC driver's mac_register() fails outright without mac/mac_ether.
    # mac_ipv4/mac_ipv6 are the same thing for the IP-over-anything pseudo
    # media that dld uses for tunnels.
    "intel/mac_ether"
    "intel/mac_ipv4"
    "intel/mac_ipv6"

    # The NIC drivers for the two things qemu will hand us: e1000g(4D) for
    # `-nic ...,model=e1000` (the default on q35/i440fx with `-net nic`) and
    # vioif(4D) for `model=virtio-net-pci`. vioif links -Nmisc/virtio.
    # Both are -N misc/mac, which is already loaded for fs/dev.
    "intel/e1000g"
    "intel/virtio"
    "intel/vioif"

    # /dev/random and /dev/urandom, via the kernel crypto framework's
    # random(4D) (-Nmisc/kcf, and crypto/swrand is the entropy provider, both
    # already above). sshd will not start without a random source, and neither
    # will anything else that seeds a PRNG.
    "intel/random"

    # The transports themselves, each -Ndrv/ip -Nfs/sockfs. These are what
    # strplumb() modloads below, and what an AF_INET socket needs; arp(7P) is
    # the STREAMS module ip plumbs under itself, and dld(7D) is the link layer
    # a NIC driver registers with -- "strplumb: failed to initialize drv/dld"
    # in the boot log is exactly this set being absent.
    "intel/tcp"
    "intel/udp"
    "intel/icmp"
    "intel/arp"
    "intel/dld"

    # main() (common/os/main.c:535) calls strplumb() unconditionally on a
    # non-networked boot. strplumb() is a *stub* (common/os/modstubs.S), so an
    # absent misc/strplumb is not a soft failure -- mod_hold_stub() panics with
    # "Couldn't load stub module misc/strplumb". The module itself has no -N
    # dependencies; it modloads the IP stack (dld, ip, tcp, udp, icmp, arp,
    # timod) at run time and merely prints "strplumb: failed to initialize ..."
    # when they are absent, which is what we want until networking is packaged.
    "intel/strplumb"

    # consconfig() (main.c:545) is a stub as well, so misc/consconfig is
    # another panic-if-absent. Its -N chain is the awkward part:
    #   consconfig       -> dacf/consconfig_dacf
    #   consconfig_dacf  -> misc/usbser  (for a USB serial console)
    #   usbser           -> misc/usba
    #   vgatext          -> misc/gfx_private
    # krtld resolves -N dependencies at modload() time whether or not the
    # hardware exists, so the USB serial stack has to be here even though the
    # console is a 16550 on ttya.
    "intel/usba"
    "intel/usbser"
    "i86pc/gfx_private"
    "i86pc/consconfig_dacf"
    "intel/consconfig"

    # ...and the modules consconfig_dacf plumbs at run time rather than links
    # against: the terminal emulator and the workstation console behind
    # /dev/console, the STREAMS modules every console line gets pushed
    # (ptem, ldterm, ttcompat), the keyboard and mouse, and asy(4D), which is
    # the actual 16550 that the -B console=ttya on the kernel command line
    # names.
    "intel/tem"
    "intel/wc"
    "intel/vgatext"
    "intel/kbtrans"
    "intel/conskbd"
    "intel/kb8042"
    "intel/consms"
    "intel/mouse8042"
    "intel/ptem"
    "intel/ldterm"
    "intel/ttcompat"

    # The pseudo-terminal pair. ptem/ldterm/ttcompat above are the STREAMS
    # modules pushed onto a terminal line; they are pushed onto pty slaves too,
    # but on their own there is no pty to push them onto.
    #
    #   ptm    the master, /dev/ptmx
    #   pts    the slave, /dev/pts/N
    #   pckt   packet mode, which the master pushes to see slave-side
    #          M_FLUSH/ioctl events -- what a job-control shell in a pty needs
    #
    # Nothing links against these (no -N in any of the three Makefiles); they
    # are opened by name. Without them there is no pty pair at all, so every
    # interactive session is impossible -- an ssh login, `login` on a virtual
    # console, script(1), screen. The serial console works without them because
    # asy(4D) is a real tty, which is why this has not bitten yet.
    #
    # /dev/pts/N does not need devfsadm: fs/dev registers a dynamic directory
    # for "pts" (sdev_subr.c:498, devpts_vnodeops) and materialises slave nodes
    # on lookup. /dev/ptmx is an ordinary devfsadm-made link, so until that
    # lands the master is reachable only under /devices.
    "intel/ptm"
    "intel/pts"
    "intel/pckt"
    "intel/asy"

    # cons_build_upper_layer() (common/io/consconfig_dacf.c:836 onwards) opens
    # four pseudo devices by path and panics on each one it cannot find:
    # /pseudo/conskbd@0:conskbd, /pseudo/consms@0:mouse, /pseudo/wc@0:wscons
    # and /pseudo/iwscn@0:iwscn (the indirect console redirection device, which
    # is what /dev/console ends up pointing at). The first three come from
    # conskbd/consms/wc above; iwscn is its own driver.
    "intel/iwscn"
    "intel/redirmod"

    # STREAMS housekeeping that anything opening a console line wants:
    # clone(4D) for /dev/xxx clone opens, sad(4D) for autopush, log(4D) for
    # strlog()/syslog.
    "intel/clone"
    "intel/sad"
    "intel/log"

    # And the thing that actually runs a program. The exec switch
    # (common/os/exec.c) is entirely modular -- there is no ELF support
    # compiled into genunix at all -- so without exec/elfexec, gexec() finds no
    # handler for the file it just opened and leaves through its `bad:` label,
    # where `if (error == 0) error = ENOEXEC` (exec.c:999). exec_init() then
    # reports "exec(/sbin/init) failed with errno 8" and start_init() calls
    # halt("unix: Could not start init") -- a silent hang, not a panic.
    # intpexec and shbinexec are the `#!` and shared-binary handlers; nothing
    # needs them yet, but any real userland will.
    "intel/elfexec"
    "intel/intpexec"
    "intel/shbinexec"

    # The PCI nexus drivers. Without these the devinfo tree has *no attached
    # hardware at all* -- /devices contains only `pseudo`, and probing from
    # userland shows /devices/isa and /devices/pci@0,0 both ENOENT. The bus
    # probe that impl_bus_initialprobe() runs (pci_autoconfig's, registered
    # through impl_bus_add_probe) does create the nodes, but a node with no
    # driver to attach never appears in devfs and can have no children -- so
    # there is no ISA bridge, and therefore no asy(4D), and therefore nothing
    # for consconfig() to plumb the console onto.
    #
    # Both root nexus drivers, because which one binds depends on the emulated
    # chipset: npe is the PCI Express one (alias pciex_root_complex, so q35),
    # pci is the legacy one (class "pci", so qemu's default i440fx). pcieb is
    # the PCI-to-PCI bridge driver, and pci needs misc/pcihp, which needs
    # misc/hpcsvc.
    "i86pc/npe"
    "intel/hpcsvc"
    "intel/pcihp"
    "i86pc/pci"
    "intel/pcieb"
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
