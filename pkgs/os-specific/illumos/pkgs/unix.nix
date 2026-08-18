{
  lib,
  runCommand,
  version,
  uts-base,
  kmod,
  buildPackages,
}:

# The i86pc kernel as a boot archive sees it: `unix` and `genunix` from
# `uts-base`, plus every loadable module in the curated list below, each of
# which is its own derivation (kmod.nix).
#
# The split exists because this list is what changes. Before it, adding one
# module meant recompiling the entire kernel -- ten minutes to find out whether
# a driver was the missing one. Now an edit here relinks one module and
# reassembles a directory of copies; `uts-base`, which is where nearly all of
# the build time lives, is untouched unless the source or the toolchain moves.
#
# Consumers copy $out/kernel, $out/platform and $out/usr wholesale (see
# nixbsd's modules/system/boot/illumos-boot-image.nix), so the layout here has
# to be the same one `install.targ` would have produced into a single $(ROOT).

let
  # The loadable modules startup_modules() and vfs_mountroot() reach for, in
  # dependency order. Each entry is a directory under usr/src/uts, and becomes
  # one `kmod` derivation.
  kmodNames = [
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

    # Needed even though nothing here is a GLDv2 device. softmac's usual job
    # is wrapping DLPI drivers in a GLDv3 MAC, which no driver we build
    # requires -- but dls calls into it on the *physical link* path
    # regardless: dls_devnet_hold_by_name() reaches softmac_hold_device()
    # (uts/common/io/dls/dls_mgmt.c:1440, :1546) to attach the device and find
    # its linkid.
    #
    # Without it that lookup cannot succeed, and all anyone sees is ifconfig
    # refusing to plumb a NIC which is present, attached, and registered with
    # dlmgmtd:
    #
    #     ifconfig: cannot plumb vioif0: Could not open DLPI link
    #
    # with /dev/net empty -- those entries being sdev's rendering of exactly
    # the datalinks this path would have found.
    #
    # Note that dls does not declare the dependency: its Makefile carries only
    # `-N misc/mac`. Upstream gets away with that because softmac is a
    # DRV_KMODS module that is always present on a real system, so the symbol
    # is always there to resolve. Building a hand-picked module list removes
    # that guarantee, and nothing warns.
    "intel/softmac"

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

    # mm(4D): /dev/null, /dev/zero, /dev/mem and /dev/kmem, whose minor nodes
    # it declares in common/io/mem.c (`null` and `zero` at 0666). Without it
    # there is no /dev/null at all, and the first thing that notices is
    # svc.startd, which cannot start a single service:
    #
    #     svc.startd: can't connect stdin to /dev/null: No such file or directory
    #
    # after which every service it tries lands in maintenance and the console
    # loops on "Console login service(s) cannot run / Requesting System
    # Maintenance Mode". No -N dependencies.
    "intel/mm"

    # dispinit() instantiates the scheduling classes named in
    # common/disp/disp.c's class table; TS is the default one and pulls in its
    # dispatch-parameter table, and SDC is what the kernel's own taskq threads
    # run under.
    "intel/TS"
    "intel/TS_DPTBL"
    "intel/SDC"

    # psm_modload() (startup.c:1649) loads every module under
    # platform/i86pc/kernel/mach and keeps the highest-priority one whose
    # probe succeeds. uppc is the plain 8259/8254 fallback that works without
    # an APIC; pcplusmp and apix drive the local APIC and the I/O APIC.
    #
    # Shipping only uppc means running on the 8259 with no I/O APIC, which is
    # not what any real illumos install does on this hardware. Note that
    # psm_get_impl_module() offers DEFAULT_PSM_MODULE -- uppc -- and nothing
    # else on its own; the rest come from /etc/mach, which the image builder
    # has to stage. With it, apix wins the probe:
    #
    #     apix: NOTICE: apic: Using APIC interrupt routing mode
    #
    # This does *not*, on its own, fix e1000g. Both under uppc and under apix
    # the boot log still carries `psm: set_irq: _SRS failed`, and e1000g's
    # attach(9E) still reaches mac_register() and then unwinds:
    #
    #     mac: NOTICE: e1000g0 registered
    #     mac: NOTICE: e1000g0 unregistered
    #
    # leaving the devinfo node bound to the driver but DI_DRIVER_DETACHED,
    # which from userland is indistinguishable from a missing driver.
    #
    # What is known about that failure, so the next person does not redo it:
    #
    #  * The register/unregister pair happens exactly once per
    #    di_init(DINFOFORCE), so it is the force-attach driving it and nothing
    #    asynchronous.
    #  * It is *not* one of the `goto attach_fail` paths that logs. Every one
    #    of those calls e1000g_log(CE_WARN, ...), which is cmn_err with a `!`
    #    prefix (e1000g_debug.c:151, e1000g_log_mode = E1000G_LOG_PRINT), and
    #    `!` messages do reach a log(4D) reader registered with I_CONSLOG --
    #    proven by "Skipping psm: xpv_psm" above, which is emitted the same
    #    way. No e1000g message appears at all.
    #  * The two silent `goto attach_fail`s (e1000g_set_driver_params and the
    #    e1000g_check_acc_handle FM check) are both *before* mac_register, so
    #    they cannot be it either.
    #  * di_devfs_path() reports the node as `/pci@0,0/pci1af4,1100` with no
    #    unit address, unlike its attached siblings (`isa@1`,
    #    `asy@1,3f8`) -- i.e. it never reached DS_INITIALIZED.
    #
    # Which leaves "attach succeeded and something detached it again inside
    # the same ndi_devi_config() walk" as the hypothesis to test next, most
    # cheaply by open(2)ing the driver's minor node to hold it.
    #
    # Both PSMs are shipped because which one probes depends on the emulated
    # chipset. Each links -N misc/acpica, which is already above.
    "i86pc/uppc"
    "i86pc/pcplusmp"
    "i86pc/apix"

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
    #
    #            All three link `-Nmisc/ipc`, which is the shared System V IPC
    #            core -- and nothing checks that, so leaving it out gives three
    #            modules that build, stage, and fail to load, with SysV IPC
    #            simply absent. Tenth instance of the same shape as net_dacf
    #            and softmac: a declared dependency nobody enforces.
    "intel/doorfs"
    "intel/portfs"
    "intel/shmsys"
    "intel/semsys"
    "intel/msgsys"
    "intel/ipc"

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

    # lofs(7FS), the loopback filesystem: what `mount -F lofs <dir> <dir>`
    # needs. There is no bind mount and no overlayfs here, so this is the only
    # way to put a writable directory over a read-only one -- which is what a
    # root on hsfs requires if anything is to write to a path with a fixed
    # name. In particular it is how /etc becomes writable so that the
    # activation script can populate it the way it does on every other
    # platform, rather than each file being hand-staged into the boot archive.
    # Installs as fs/lofs and has no -N dependencies.
    "intel/lofs"

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

    # drv/ip6, which is a separate module from drv/ip even though the v6
    # implementation lives inside ip. strplumb() modloads it by name, and it is
    # not optional there: with it absent the boot log carries
    #
    #     strplumb: failed to initialize drv/ip6
    #
    # and plumbing stops at that point, so no interface -- v4 included -- ever
    # comes up. It links -Ndrv/ip and nothing else.
    "intel/ip6"

    "intel/sockfs"

    # The NFS *client*, so the store can be served read-only from the host
    # instead of being copied into a per-build image and then into RAM.
    #
    # The dependency chain is declared, so this list is taken from the module
    # makefiles rather than guessed -- guessing a hand-picked module list is
    # what cost a full day of driver debugging when net_dacf turned out to be
    # missing:
    #
    #     nfs     -N fs/specfs -N strmod/rpcmod -N misc/rpcsec
    #     rpcmod  -N misc/tlimod
    #
    # specfs is already above. `klmmod`/`klmops` are deliberately absent: they
    # are the NLM lock manager, which NFSv3 needs and NFSv4 does not -- v4
    # carries locking in the protocol itself with leases. Add them only if
    # something turns out to want v3.
    #
    # nfssrv is also absent, on purpose. We are the client; the server runs on
    # the host as an ordinary user process (nfs-ganesha), which is what keeps
    # this from needing root anywhere.
    "intel/tlimod"
    "intel/rpcsec"
    "intel/rpcmod"
    "intel/nfs"

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

    # virtio-blk, for a root filesystem on a disk rather than a ramdisk. The
    # boot archive is currently a multiboot module that GRUB copies into memory
    # whole before the kernel starts -- which is most of boot time, and is why
    # the root is hsfs and therefore read-only. A disk is read on demand and can
    # carry a writable filesystem (`ufs` and `fssnap_if` are already above).
    #
    # `vioblk` gives a block device, not files, so this only pays off with a
    # filesystem image on it. The dependency chain is
    # vioblk -Nmisc/virtio -Ndrv/blkdev, blkdev -Nmisc/cmlb, and cmlb has none.
    #
    # (illumos also ships vio9p, but that is only the 9P *transport* -- "a 9P
    # file system will use LDI to open this device" -- and there is no 9P
    # filesystem in the gate, so the host's store cannot be shared in the way
    # NixOS's own VM tests do it.)
    "intel/cmlb"
    "intel/blkdev"
    "intel/vioblk"

    # The Virtio FS client, which is the other way to get the host's store in:
    # `drv/vtfs` owns the 1af4:105a PCI device and does the virtqueue round
    # trips, `fs/virtiofs` speaks FUSE over it. Two modules rather than one
    # because a module lives in exactly one of kernel/drv and kernel/fs, and
    # this has to be found both by the device tree and by domount().
    #
    # vtfs -Nmisc/virtio; virtiofs -Nfs/specfs -Ndrv/vtfs. All already above.
    "intel/vtfs"
    "intel/virtiofs"

    # /dev/random and /dev/urandom, via the kernel crypto framework's
    # random(4D) (-Nmisc/kcf, and crypto/swrand is the entropy provider, both
    # already above). sshd will not start without a random source, and neither
    # will anything else that seeds a PRNG.
    "intel/random"

    # devinfo(4D), the snapshot device behind libdevinfo. Every consumer of the
    # device tree goes through it -- di_init(3DEVINFO) opens
    # /devices/pseudo/devinfo@0:devinfo and reads a packed snapshot -- so
    # without it `prtconf`, `devfsadm` and `dladm show-phys` have no way to see
    # hardware at all. It is also the only way to ask the kernel to *attach*
    # nodes it has merely bound: DINFOFORCE is what makes di_init walk the tree
    # calling ndi_devi_config(), which is how a NIC on the PCI bus comes up on
    # a system where nothing else has opened it.
    "intel/devinfo"

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

    # The v6 halves of the same transports. strplumb() plumbs v6 as well as v4
    # and does not treat a missing one as optional, so leaving these out stops
    # plumbing dead even for a v4-only system -- the boot log walks the list
    # one at a time as each is supplied:
    #
    #     strplumb: failed to initialize drv/ip6
    #     strplumb: failed to initialize drv/tcp6
    #
    # and so on. They are separate modules from their v4 namesakes even though
    # the implementations share source.
    "intel/tcp6"
    "intel/udp6"
    "intel/icmp6"

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

    # The *other* DACF module, and the one that makes networking exist.
    #
    # /etc/dacf.conf -- which we stage -- carries these two rules:
    #
    #     minor-nodetype="ddi_network" net_dacf:net_config post-attach -
    #     minor-nodetype="ddi_network" net_dacf:net_config pre-detach -
    #
    # so every `ddi_network` minor node's post-attach is supposed to run
    # net_postattach() (uts/common/io/net_dacf.c:104), which calls
    # softmac_create(), which calls dls_devnet_create(). That is what turns an
    # attached NIC into a *datalink* -- and, crucially, what takes the
    # reference that keeps the driver attached.
    #
    # Without this module the rule names a module that cannot be loaded, and
    # a NIC gets all the way through attach and then evaporates:
    #
    #     mac: NOTICE: vioif0 registered
    #     mac: NOTICE: vioif0 unregistered      <- two ticks later
    #
    # vioif_attach() itself returns DDI_SUCCESS with no diagnostic; instance 0
    # is assigned, interrupts are enabled, mac_register() succeeds. Nothing is
    # wrong with the driver. It is simply that nobody holds it, because the
    # thing that would hold it never ran. Every downstream symptom follows:
    # no datalink for dlmgmtd to know about, /dev/net empty (those entries are
    # sdev rendering the datalinks), and finally
    #
    #     ifconfig: cannot plumb vioif0: Could not open DLPI link
    #
    # which is three layers away from the cause and blames the driver.
    "intel/net_dacf"

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

    # `/dev/poll` (uts/common/io/devpoll.c, built from uts/intel/poll). This is
    # illumos' scalable readiness interface, the local equivalent of epoll or
    # kqueue, and any server that expects to hold many connections reaches for
    # it before poll(2).
    #
    # nginx does exactly that: it selects the `/dev/poll` event method at
    # configure time for this platform, and without the driver its worker dies
    # immediately at startup with
    #
    #     [emerg] open(/dev/poll) failed (2: No such file or directory)
    #     [alert] worker process ... exited with fatal code 2 and cannot be
    #             respawned
    #
    # while the MASTER stays up holding the listen socket. So SMF reports the
    # service `online`, `svcs -p` shows an nginx process, connections to port 80
    # are accepted -- and every one of them returns nothing, because nobody is
    # left to serve them. Nothing in the service log says why: nginx's
    # `error_log stderr` output is the only place that message appears.
    #
    # Like ptm/pts/pckt above, nothing links against it; it is opened by name.
    "intel/poll"

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

    # ZFS. `drv/zfs` is the whole filesystem, the ZVOL block driver and the
    # /dev/zfs ioctl device in one module; uts/intel/zfs/Makefile installs it
    # once and hardlinks it as `fs/zfs` as well (`$(ROOTLINK): ln
    # $(ROOTMODULE) $@`), which is why the copy in the recipe below has to
    # keep `--preserve=links`.
    #
    # Its `-N` list is `fs/specfs crypto/swrand misc/idmap misc/sha2
    # misc/skein misc/edonr`; specfs is already above, and the rest come with
    # dependencies of their own:
    #
    #   crypto/swrand   the kernel entropy provider. -Nmisc/kcf -Nmisc/sha1.
    #   misc/sha2       } the checksum algorithms `zfs set checksum=` names.
    #   misc/skein      } All three are KCF providers, so all three link
    #   misc/edonr      } -Nmisc/kcf.
    #   misc/kcf        the Cryptographic Framework core they register with.
    #   misc/idmap      SID<->uid/gid mapping for the NFSv4-style ACLs ZFS
    #                   stores. It links -Nsys/doorfs (already above; the
    #                   mapping requests go to idmapd over a door) and
    #                   -Nstrmod/rpcmod, whose own -Nmisc/tlimod brings the
    #                   TLI transport code with it.
    #
    # None of the checksum modules are as optional as "we never asked for
    # skein" suggests: zio_checksum_table[] (common/fs/zfs/zio_checksum.c) is
    # indexed by whatever the on-disk label says, so a pool created elsewhere
    # can name any of them.
    #
    # Only the modules ZFS is the first to need are entries here: kcf, sha1,
    # swrand, tlimod and rpcmod are all already in the sockets and NFS blocks
    # above, and were repeated here until they were noticed. Listing a module
    # twice builds and copies the same derivation twice, which the build
    # survives -- but `passthru.kmodBaseNames` carries the duplicates out to
    # consumers, including the /etc data-file check in nixbsd's
    # illumos-boot-image.nix. The chain above stays written out in full on
    # purpose: it is the documentation for why those other blocks may not
    # shrink.
    "intel/sha2"
    "intel/skein"
    "intel/edonr"
    "intel/idmap"
    "intel/zfs"
  ];
in

# `runCommand` from the illumos scope rather than `buildPackages.runCommand`:
# it is stdenvNoCC, so nothing is compiled here and the recipe still runs on
# the build machine, but the derivation keeps solaris as its host platform.
# That is what makes `meta.platforms = platforms.illumos` -- shared with every
# other package in this scope -- come out as supported rather than as an
# unsupported-system evaluation failure.
runCommand "unix-illumos-${version}"
  {
    passthru = {
      inherit uts-base;

      # The module list, and the bare module names it provides
      # (`intel/net_dacf` -> `net_dacf`).  Exposed so that the image builder
      # can check the *data files* that name modules by bare name --
      # `/etc/dacf.conf` names `net_dacf`, `/etc/driver_aliases` names a
      # driver per line -- against what was actually built.  Same failure
      # shape as the -N check below, one layer out: a rule naming a module
      # that cannot be loaded is silently a no-op.
      inherit kmodNames;
      kmodBaseNames = map baseNameOf kmodNames;
      # The individual modules, so that a bring-up session can build and
      # inspect one on its own: `nix-build -A illumos.unix.kmods.intel-vioif`.
      kmods = builtins.listToAttrs (
        map (m: {
          name = lib.replaceStrings [ "/" ] [ "-" ] m;
          value = kmod m;
        }) kmodNames
      );
    };

    meta = with lib; {
      maintainers = with maintainers; [ ericson2314 ];
      platforms = platforms.illumos;
      license = licenses.cddl;
    };
  }
  # A copy rather than symlinkJoin: the image builders that consume this
  # reach in with plain `cp -r "$kernel/kernel"` (nixbsd's
  # modules/system/boot/illumos-boot-image.nix), and a tree of symlinks into
  # the store would land in the boot archive as dangling links unless every
  # one of them remembered -L. The copies are nearly free on a filesystem
  # that reflinks.
  #
  # --no-preserve=mode because the store paths are read-only and the second
  # cp into an existing directory would otherwise have nowhere to write.
  #
  # --preserve=links because a module installed under two names is one file
  # with two links, not two files: uts/intel/ip/Makefile:119 is
  # `ln $(ROOTMODULE) $@`, so kernel/drv/amd64/ip and kernel/strmod/amd64/ip
  # are the same inode, and nfs does the same across kernel/fs and kernel/sys.
  # Plain `cp -r` breaks the link and doubles them in the boot archive.
  (
    ''
      mkdir -p "$out"
      for d in ${uts-base} ${lib.concatMapStringsSep " " (m: "${kmod m}") kmodNames}; do
        cp -r --preserve=links --no-preserve=mode "$d/." "$out/"
      done

    ''
    # Now that the tree is assembled, check that every `-N <class>/<name>`
    # dependency any staged module declares names a module which is actually
    # here.  Nothing else in the build does: krtld resolves those at modload()
    # time, so an entry missing from `kmodNames` above costs nothing until the
    # machine is running, and then costs a day -- the module quietly fails to
    # load and something three layers up misbehaves.  See the header comment
    # in check-kmod-deps.py.
    #
    # Read-only: it walks $out and exits non-zero.  It cannot perturb the
    # output.
    + ''
      ${buildPackages.python3Minimal}/bin/python3 ${./check-kmod-deps.py} \
        "$out" pkgs/os-specific/illumos/pkgs/unix.nix \
        ${lib.escapeShellArgs kmodNames}
    ''
  )
