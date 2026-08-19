{
  mkDerivation,

  cw,

  libbsm,
  libdevid,
  libdevinfo,
  libgen,
  libnvpair,
  libsysevent,
  sys-intel,
}:

# devfsadm(8) -- usr/src/cmd/devfsadm.
#
# This is what populates /dev. The kernel's devfs gives you /devices, a tree of
# real device nodes named after the device tree; every familiar name under /dev
# (/dev/dsk/c0t0d0s0, /dev/rdsk/*, /dev/console, /dev/rdisk, ...) is a symlink
# into /devices that devfsadm creates. Without it a Nix-built illumos has
# /devices and essentially nothing else, so nothing can be mounted by device
# name and /dev has to be hand-written.
#
# The build is unusual for a command: cmd/devfsadm/Makefile.com includes *both*
# lib/Makefile.lib and cmd/Makefile.cmd, because the package produces a program
# (devfsadm) plus a pile of shared objects (SUNW_*_link.so) that devfsadm
# dlopens at run time to get the per-class link rules. That is why the flags
# below have to tame `DYNFLAGS` as well as the usual `LDFLAGS.cmd`.
mkDerivation {
  pname = "devfsadm";

  # The per-ISA subdirectory, not the top of cmd/devfsadm: like most of these
  # commands there is no `amd64` directory, only `i386`, and the 64-bit macros
  # are supplied on the command line instead (see makeFlags). Building `i386`
  # directly also skips the top Makefile's install rules, which want to write
  # into /etc.
  path = "usr/src/cmd/devfsadm/i386";

  # Its makefiles index source, object or install directories by $(MACH) /
  # $(MACH64), so it needs the illumos spelling of the CPU. Not the default:
  # setting MACH for a package whose install rules do not expect it relocates
  # that package's output. See `machMakeFlags` in mkDerivation.nix.
  illumosMach = true;

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # $(MAPFILE.NES), $(MAPFILE.PGA) and $(MAPFILE.NED) -- the non-executable
    # stack/data and page-alignment mapfiles Makefile.cmd puts on every command
    # through $(LDFLAGS.cmd). GNU ld read -M as "write a link map" and never
    # opened them; illumos ld does, and stops if they are not there.
    "usr/src/common/mapfiles"

    # The common half of the command: Makefile.com, all the *_link.c link
    # modules, devfsadm.c itself, the mapfile and devlink.tab.sh.
    "usr/src/cmd/devfsadm"

    # `Makefile.com` has a rule that materialises ../plcysubr.c as a symlink to
    # ../modload/plcysubr.c -- the device-policy parser is shared verbatim with
    # add_drv/update_drv rather than living in a library; its own header is
    # reached through -I$(MODLOADDIR), which is that same directory.
    # `plcysubr.c` also includes "addrem.h" (and, through it, "errmsg.h"), the
    # add_drv/rem_drv internals -- it is written as part of that command, not
    # as a standalone file.
    "usr/src/cmd/modload/plcysubr.c"
    "usr/src/cmd/modload/plcysubr.h"
    "usr/src/cmd/modload/addrem.h"
    "usr/src/cmd/modload/errmsg.h"

    # Makefile.com puts -I$(UTSBASE)/common on everything, and the link
    # modules lean on it: they are matching against the driver-private ioctl
    # and minor-node interfaces (<sys/cpuid_drv.h>, <sys/lofi.h>,
    # <sys/ramdisk.h>, ...), most of which are kernel-internal and never
    # installed into /usr/include, so the headers package cannot supply them.
    "usr/src/uts/common/sys"

    # i386/Makefile puts -I$(UTSBASE)/i86xpv on xen_link.o for
    # <sys/privcmd_impl.h>, <sys/domcaps_impl.h> and <sys/balloon.h>. These are
    # paravirt-only interfaces, likewise not installed anywhere.
    "usr/src/uts/i86xpv/sys"

    # `devfsadm_impl.h` includes <device_info.h>, the private half of
    # libdevinfo's interface (the `devfs_*` minor-node walkers). Upstream
    # installs it into /usr/include from the *top* lib/libdevinfo Makefile,
    # which the libdevinfo package does not run -- it builds the amd64
    # subdirectory directly, and only ships <libdevinfo.h>. Point at the source
    # directory instead, exactly as getent.nix does for <libsocket_priv.h>.
    "usr/src/lib/libdevinfo/device_info.h"
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    # -ldevinfo (di_*), and libdevinfo is also where <sys/devinfo_impl.h> and
    # the rest of the device-tree headers come from.
    libdevinfo
    # -ldevid on the disk and sgen link modules: disk_link.c builds /dev/dsk
    # and /dev/rdsk names for SAS targets with `scsi_lun64_to_lun` and
    # `scsi_wwnstr_to_wwn`, which live in libdevid. See libdevid.nix, which
    # exists only because of this.
    libdevid
    # -lgen, for the regex/utility routines the link modules use.
    libgen
    # -lsysevent and -lnvpair: the daemon half (devfsadmd) subscribes to the
    # sysevent channel so that hotplug events create links as they happen.
    libsysevent
    libnvpair
    # -lbsm, for the device-allocation database (<bsm/devalloc.h>) that
    # devalloc.c maintains.
    libbsm
    # misc_link_i386.c includes <sys/mc_amd.h>, an uts/intel header.
    sys-intel
  ];

  # Drop -lzonecfg, and with it the one function that needs it.
  #
  # devfsadm's entire use of libzonecfg is zone_pathcheck(), a sanity check
  # that refuses `devfsadm -r <path>` when <path> lies inside some
  # non-global zone's zonepath: it walks /etc/zones/index with
  # setzoneent()/getzoneent() and compares each zonepath against the
  # requested root. Linking libzonecfg for that would drag in libscf,
  # libuuid, libxml2, libbrand and the zone-configuration schema -- a large
  # sub-project for a check that is inherently a no-op on a system with no
  # zones configured, which is every system this port currently produces.
  #
  # This is not even a behaviour change in the usual sense. Upstream already
  # treats libzonecfg as optional here: the first thing zone_pathcheck()
  # does is `dlopen(LIBZONECFG_PATH)` and `return (DEVFSADM_SUCCESS)` if that
  # fails -- the direct calls below it are only reached once the dlopen has
  # proved zones are present. So on a zone-less system the function returns
  # success immediately anyway, and the stub returns exactly the same thing.
  # The body is removed rather than merely made unreachable because the
  # undefined references would still be in the object file otherwise.
  #
  # If zones are ever ported, revert this and add libzonecfg back.
  postPatch = ''
    substituteInPlace usr/src/cmd/devfsadm/Makefile.com \
      --replace-fail 'LDLIBS += -lgen -lsysevent -lnvpair -lzonecfg -lbsm' \
                     'LDLIBS += -lgen -lsysevent -lnvpair -lbsm'

  ''
  # ...and the header with it. <libzonecfg.h> is installed (it is a public
  # header) but it includes <libbrand.h>, which is not, because nothing has
  # built lib/libbrand. Every name devfsadm took from it -- LIBZONECFG_PATH,
  # GLOBAL_ZONENAME, Z_OK -- is used only inside the function removed below;
  # getzoneid()/GLOBAL_ZONEID elsewhere in devfsadm.c come from <zone.h> in
  # libc and are unaffected.
  + ''
    substituteInPlace usr/src/cmd/devfsadm/devfsadm_impl.h \
      --replace-fail '#include <libzonecfg.h>' \
                     '/* <libzonecfg.h> dropped; see devfsadm.nix */'

    substituteInPlace usr/src/cmd/devfsadm/devfsadm.c \
      --replace-fail 'zone_pathcheck(char *checkpath)
    {' 'zone_pathcheck(char *checkpath)
    {
    	/* See devfsadm.nix: libzonecfg is not packaged. */
    	return (DEVFSADM_SUCCESS);
    }

    #if 0
    static int
    zone_pathcheck_disabled(char *checkpath)
    {' \
      --replace-fail '/*
     *  Called by the daemon when it receives an event from the devfsadm SLM' '#endif	/* 0 -- see devfsadm.nix */

    /*
     *  Called by the daemon when it receives an event from the devfsadm SLM'

  ''
  # The link modules are found by scanning a compiled-in directory
  # (MODULE_DIRS, overridable only with the undocumented -l flag), so the
  # default has to name this package's own store path or a plain `devfsadm`
  # invocation finds no modules at all and creates no links.
  #
  # The remaining compiled-in paths -- /etc/devlink.tab, /etc/dev, /dev,
  # /devices -- are deliberately left alone: those are system state and
  # configuration, not parts of this package, and they must resolve on the
  # running machine.
  + ''
    substituteInPlace usr/src/cmd/devfsadm/devfsadm_impl.h \
      --replace-fail '#define	MODULE_DIRS "/usr/lib/devfsadm/linkmod"' \
                     "#define	MODULE_DIRS \"$out/lib/devfsadm/linkmod\""
  '';

  # Through `makeFlagsArray` rather than `makeFlags` because the value contains
  # a space, and `makeFlags` entries are word-split. `CPPFLAGS.first` rather
  # than `CPPFLAGS` so that Makefile.master's own -D flags survive. See the
  # lib/libdevinfo entry in extraPaths for why this is needed.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I\$(SRC)/lib/libdevinfo")
  '';

  makeFlags = [
    # cmd/devfsadm has no amd64 subdirectory, so upstream builds it 32-bit.
    # This port is 64-bit only -- there is no 32-bit libc packaged -- so the
    # macros Makefile.cmd.64 would have set are passed here instead. See
    # getent.nix, which does the same for the same reason.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # `$(POST_PROCESS)` and friends end in strip/CTF steps that need illumos
    # target tools on the build host, and nothing here consumes CTF.
    # POST_PROCESS_SO matters as well as the usual two, because this package
    # builds shared objects through lib/Makefile.lib's machinery.
    "POST_PROCESS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_SO=:"

    # Solaris link-editor syntax that GNU ld rejects; see getent.nix for why
    # none of it is load-bearing for a command.
    #
    # There used to be a `LDFLAGS.cmd=-Wl,--export-dynamic` here as well, and it
    # was load-bearing. The relationship between devfsadm and its link modules
    # runs both ways: devfsadm dlopen()s them, and they call back into it,
    # referencing symbols such as `devfsadm_rm_all` and `system_labeled` that
    # are defined in the *executable* rather than in any library. Solaris' link-
    # editor puts an executable's globals in .dynsym so that resolves; GNU ld
    # does not unless asked, so with GNU ld every module failed to load at run
    # time:
    #
    #   devfsadm: dlopen failed: .../SUNW_disk_link.so: ld.so.1: devfsadm:
    #     fatal: relocation error: ... symbol system_labeled:
    #     referenced symbol not found
    #
    # and devfsadm still exited 0, having only logged each failure -- so /dev
    # stayed empty with nothing to say why.
    #
    # The link-editor is now illumos' own (../bintools.nix), which needs no
    # asking, and has no `--export-dynamic` to ask with: the flag is a GNU-ism
    # it rejects outright. So the workaround goes, and the behaviour it was
    # buying comes back for free.
    "LDCHECKS="

    # The same problem one level over, for the shared objects. Makefile.lib's
    #
    #   DYNFLAGS = $(HSONAME) $(ZTEXT) $(ZDEFS) $(BDIRECT) \
    #              $(MAPFILES:%=-Wl,-M%) ... $(LDCHECKS)
    #
    # is passed to the compiler driver, which here reaches GNU ld. $(BDIRECT)
    # is Solaris-only, and -M is actively dangerous rather than merely
    # rejected: to GNU ld it means "write a link map", so the mapfile name
    # would be consumed as an output path and the version script silently
    # ignored. Clearing the whole macro is right because none of it is needed
    # for these particular objects -- they are dlopen'd plugins, not versioned
    # public libraries, and devfsadm reaches into them by dlsym'ing a fixed set
    # of names that GNU ld exports by default. The -h soname the modules do
    # need is supplied separately by Makefile.com's own SUNW_%.so rule
    # (`-Wl,-h$@`), which is why nulling DYNFLAGS does not lose it.
    "DYNFLAGS="
  ];

  # `all` rather than `install`: upstream's install rules want $(ROOTETC) and
  # $(ROOTUSRSBIN), neither of which the setup hook redirects into $out, and
  # they also drop hard links and a relative symlink that are easier to write
  # out explicitly below.
  buildFlags = [ "all" ];
  dontInstall = false;

  installPhase = ''
    runHook preInstall

  ''
  # Upstream installs the program in /usr/sbin and the link modules in
  # /usr/lib/devfsadm/linkmod; the same shape is kept here, minus the /usr.
  # nixpkgs' fixup then folds $out/sbin into $out/bin and leaves
  # `$out/sbin -> bin` behind, so the relative devfsadmd symlink below keeps
  # resolving either way.
  #
  # `mkdir`/`cp` rather than `install -D`: the `install` on PATH is illumos'
  # own (mkDerivation puts it there) and it does not take -D.
  + ''
    mkdir -p $out/sbin $out/lib/devfsadm/linkmod $out/etc

    cp devfsadm $out/sbin/devfsadm
    chmod 755 $out/sbin/devfsadm
    cp SUNW_*.so $out/lib/devfsadm/linkmod/
    chmod 755 $out/lib/devfsadm/linkmod/*.so

  ''
  # devfsadm decides what it is doing from argv[0]; upstream makes these
  # hard links to the one binary in /usr/sbin. `devlinks` and `drvconfig` in
  # particular are what the SMF device services actually invoke.
  + ''
    for compat in disks tapes ports audlinks devlinks drvconfig; do
      ln $out/sbin/devfsadm $out/sbin/$compat
    done

  ''
  # The daemon is the same binary again, under the name that makes it run in
  # daemon mode. Upstream puts it at /usr/lib/devfsadm/devfsadmd.
  + ''
    ln -s ../../sbin/devfsadm $out/lib/devfsadm/devfsadmd

  ''
  # The generic name-to-link rules, generated from devlink.tab.sh. Upstream
  # installs this as /etc/devlink.tab; it is configuration, so it is shipped
  # here for a system to copy or symlink into place rather than being
  # referenced from the store.
  + ''
    cp devlink.tab $out/etc/devlink.tab
    chmod 644 $out/etc/devlink.tab

  ''
  # Likewise /etc/dev/reserved_devnames, read at startup to keep enumerated
  # names (c0, c1, ...) from being reused.
  + ''
    mkdir -p $out/etc/dev
    cp ../reserved_devnames $out/etc/dev/reserved_devnames
    chmod 644 $out/etc/dev/reserved_devnames

    runHook postInstall
  '';

  meta = {
    description = "illumos /dev administration daemon and its link modules";
    mainProgram = "devfsadm";
  };
}
