{
  mkDerivation,

  crt,
  headers,
  libcMinimal,
  libssp_ns,

  libdevinfo,
  libinetutil,
  libsocket,
  libscf,
  librcm,
  libnvpair,
  libexacct,
  libkstat,
  libpool,
  libvarpd,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path. libscf and
  # libdevinfo bring the libsec/libidmap/libuutil/libgen/libsmbios cluster,
  # libpool brings libxml2, libvarpd brings libavl/libumem/libidspace/librename,
  # and libsocket brings libnsl (and thence libmd/libmp).
  libgen,
  libsmbios,
  libuutil,
  libsec,
  libavl,
  libidmap,
  libumem,
  libidspace,
  librename,
  libxml2,
  libnsl,
  libmd,
  libmp,
}:

let
  runtimeLibs = [
    libdevinfo
    libinetutil
    libsocket
    libscf
    librcm
    libnvpair
    libexacct
    libkstat
    libpool
    libvarpd
    libgen
    libsmbios
    libuutil
    libsec
    libavl
    libidmap
    libumem
    libidspace
    librename
    libxml2.out
    libnsl
    libmd
    libmp
  ];
  linkPaths = builtins.toString (
    [
      "-L${libcMinimal}/lib"
      "-L${libssp_ns}/lib"
    ]
    ++ map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# libdladm.so.1 -- the datalink administration library. Everything that names
# a datalink goes through here: `dladm_name2info`/`dladm_datalink_id2info` to
# resolve a link name against dlmgmtd's namespace, the link-property machinery
# (`linkprop.c`), and the creation entry points for the software link types
# (VNICs, VLANs, aggregations, IP tunnels, simnets, bridges, overlays).
#
# It is the reason this branch of the tree got packaged at all: `ifconfig`
# links `-ldladm`, and so does `libipadm`. Plumbing an interface means asking
# libdladm for the link's id and class first.
#
# Note that at run time most of this wants dlmgmtd (the datalink management
# daemon) on the other end of a door, which is not packaged: link *lookup* for
# a physical NIC still works, because libdladm falls back to walking the
# device tree through libdevinfo when the door is unavailable, but creating a
# persistent link would not.
#
# The dependency list is long and almost none of it is wanted for its own
# sake. `-lrcm` is the reconfiguration coordination client, `-lvarpd` the
# overlay plugin framework, `-lpool`/`-lexacct` the flow accounting side, and
# `-lscf` the persistent-property backing store in SMF. All are hard
# requirements of the link, because the illumos link-editor runs with -zdefs.
mkDerivation {
  libcMinimal = true;
  illumosLib = true;
  path = "usr/src/lib/libdladm/amd64";
  pname = "libdladm";

  outputs = [
    "out"
    "dev"
  ];

  extraPaths = [
    "usr/src/lib/Makefile.lib.64"
    # Makefile.com includes it: libdladm is a /lib library, since ifconfig and
    # dladm live in /sbin and must work before /usr is mounted.
    "usr/src/lib/Makefile.rootfs"
    "usr/src/lib/libdladm"

    # Two headers libdladm's sources include but whose libraries it does not
    # link, so they arrive through no buildInput and have to come from the
    # source tree:
    #
    #  * <libdlpi.h> -- `libdllink.c` uses the DLPI type constants and
    #    `dlpi_walk` to enumerate physical links. The dependency is one-way:
    #    libdlpi links -ldladm, not the other way around, so taking the header
    #    alone here is what breaks the cycle rather than a workaround.
    #
    #  * <libvrrpadm.h> -- `libdlmgmt.c` speaks the VRRP daemon's door
    #    protocol directly (`dladm_dld_ioc`-style requests to vrrpd) rather
    #    than linking libvrrpadm, so it needs only the protocol declarations.
    #  * <uid_stp.h> -- `libdlbridge.h` includes it for the bridge/port state
    #    types shared with the RSTP daemon. libdladm does not link librstp
    #    either: the bridge entry points reach `rstpd` over a door and only
    #    need the shared structure definitions.
    "usr/src/lib/libdlpi/common"
    "usr/src/lib/libvrrpadm/common"
    "usr/src/lib/librstp/common"

    "usr/src/common/mapfiles"
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
    libdevinfo
    libinetutil
    libsocket
    libscf
    librcm
    libnvpair
    libexacct
    libkstat
    libpool
    libvarpd
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  buildFlags = [ "all" ];

  # Each `dev` output named here supplies a header that libdladm includes with
  # angle brackets and that upstream would have found in the proto area. They
  # have to precede the `-I../common` Makefile.com adds, which is why this goes
  # through CPPFLAGS.first.
  #
  # See libm.nix for why `BUILD.SO` has to be redefined to call `$(LD)`
  # directly, and libnsl.nix for why crti.o/crtn.o have to be named explicitly
  # once the compiler driver is out of the picture. Every `-L` gets a matching
  # `-R`: without it there is no DT_RUNPATH and no nix reference, so the
  # dependency is absent from the closure and never reaches the boot archive.
  preBuild = ''
    makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I${libdevinfo.dev}/include -I${libinetutil.dev}/include -I${libscf.dev}/include -I${librcm.dev}/include -I${libnvpair.dev}/include -I${libkstat.dev}/include -I${libpool.dev}/include -I${libvarpd.dev}/include -I\$(SRC)/lib/libdlpi/common -I\$(SRC)/lib/libvrrpadm/common -I\$(SRC)/lib/librstp/common")
    makeFlagsArray+=("BUILD.SO=\$(LD) -o \$@ \$(GSHARED) \$(DYNFLAGS) ${crt}/lib/crti.o \$(PICS) \$(EXTPICS) ${crt}/lib/crtn.o ${linkPaths} \$(LDLIBS)")
  '';

  # The header list is the *top* lib/libdladm Makefile's `HDRS`, which we do
  # not run: the amd64 subdirectory is built directly. The `_impl` headers are
  # in upstream's install list too -- dladm(8) and the flow commands share
  # those structures -- so they are copied along with the public ones.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib"
    cp libdladm.so.1 "$out/lib/"
    ln -s libdladm.so.1 "$out/lib/libdladm.so"

    mkdir -p "$dev/include"
    cp ../common/libdladm.h ../common/libdladm_impl.h ../common/libdllink.h \
      ../common/libdlaggr.h ../common/libdlwlan.h ../common/libdlwlan_impl.h \
      ../common/libdlvnic.h ../common/libdlvlan.h ../common/libdlmgmt.h \
      ../common/libdlflow.h ../common/libdlflow_impl.h ../common/libdlstat.h \
      ../common/libdlether.h ../common/libdlsim.h ../common/libdlbridge.h \
      ../common/libdliptun.h ../common/libdlib.h ../common/libdloverlay.h \
      "$dev/include/"

    runHook postInstall
  '';
}
