{
  mkDerivation,

  cw,

  libpam,
  libbsm,
  libcontract,
  libscf,
  # The DT_NEEDEDs of the above, transitively; the illumos link-editor insists
  # on finding a shared object's dependencies on the link path.
  libsecdb,
  libtsol,
  libinetutil,
  libnvpair,
  libuutil,
  libgen,
  libsmbios,
  libdevinfo,
  libsec,
  libavl,
  libidmap,
  libnsl,
  libsocket,
  libmd,
  libmp,
}:

let
  runtimeLibs = [
    libpam
    libbsm
    libcontract
    libscf
    libsecdb
    libtsol
    libinetutil
    libnvpair
    libuutil
    libgen
    libsmbios
    libdevinfo
    libsec
    libavl
    libidmap
    libnsl
    libsocket
    libmd
    libmp
  ];
  linkPaths = builtins.toString (
    map (p: "-L${p}/lib -R${p}/lib") runtimeLibs
  );
in

# init(8) -- the real one, out of usr/src/cmd/init, as opposed to the
# freestanding `init-stub`/`init-shell` this bring-up has been booting so far.
#
# What it does that the stubs do not: read /etc/default/init for the initial
# environment, run the `inittab` entries, and -- the part that matters here --
# start `svc.startd` and restart it if it dies. On a modern illumos almost
# everything else init used to do belongs to SMF; init keeps the legacy
# run-level machinery and the console `sulogin` fallback.
#
# It authenticates through PAM (`-lpam`) for that sulogin path, audits through
# `-lbsm`, holds svc.startd in a process contract (`-lcontract`) so it learns
# when the whole tree dies rather than just the first process, and reads the
# repository through `-lscf`.
#
# `zone_initname` is the literal string "/sbin/init" (uts/common/os/main.c),
# so the binary has to land at $out/sbin/init and stay there -- hence
# `dontMoveSbin`, as for the stubs.
mkDerivation {
  pname = "illumos-init";
  path = "usr/src/cmd/init";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # `OBJS = init.o bootbanner.o definit.o ilstr.o`: three of the four are
    # compiled out of shared source directories rather than cmd/init.
    "usr/src/common/definit"
    "usr/src/common/bootbanner"
    "usr/src/common/ilstr"

    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [
    cw
  ];

  buildInputs = [
    libpam
    libbsm
    libcontract
    libscf
    libnvpair
  ];

  preBuild = ''
    makeFlagsArray+=("LDFLAGS.cmd=${linkPaths}")
  '';

  makeFlags = [
    "MACH=i386"
    "MACH64=amd64"

    # cmd/init has no amd64 subdirectory -- upstream builds it 32-bit -- so
    # the macros `Makefile.cmd.64` would have set are passed on the command
    # line instead, as svccfg.nix, svc-configd.nix and svc-startd.nix do.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    # The link goes through the compiler driver, hence GNU ld; see getent.nix
    # for why `LDCHECKS` has to be emptied, and svccfg.nix for `MAPFILES`.
    "LDCHECKS="
    "MAPFILES="
    "CTFMERGE_HOOK="

    # cmd/Makefile.cmd:485 gives every $(ROOTFS_PROG) an explicit
    # `-Wl,-I/lib/ld.so.1`, so that a program in the root filesystem uses an
    # interpreter that exists before /usr is mounted. That path is the 32-bit
    # one, and the guard in front of it -- `$(64ONLY)`, which is `$(POUND_SIGN)`
    # only on sparc -- assumes the x86 build of these commands is 32-bit,
    # which ours is not. The result is a 64-bit init whose PT_INTERP is
    # /lib/ld.so.1, and the kernel then rejects it with
    #
    #     WARNING: exec(/sbin/init) failed (file not found)
    #
    # naming the binary rather than the interpreter it could not find.
    #
    # Comment the line out instead of correcting the path to
    # /lib/amd64/ld.so.1: there is no /lib/amd64 in this image either, and
    # with the macro gone the nixpkgs cc-wrapper supplies its usual absolute
    # store PT_INTERP -- which is how every other dynamically linked program
    # here, bash included, already resolves its interpreter.
    "64ONLY=$(POUND_SIGN)"
  ];

  # As for init-stub and init-shell: keep the binary at $out/sbin/init rather
  # than letting move-sbin-to-bin.sh relocate it.
  dontMoveSbin = true;

  # `install` also removes /etc/init and /usr/sbin/init compat links and
  # installs /etc/default/init, none of which we want against a live ROOT.
  # Install by hand instead.
  # `install` on $PATH here is illumos' own (cmd/install), not GNU coreutils,
  # so no -D and no -m in the combined form -- hence plain mkdir/cp/chmod.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/sbin" "$out/bin" "$out/share/illumos"
    cp init "$out/sbin/init"
    chmod 755 "$out/sbin/init"

    # nixbsd's top-level.nix links "<getBin system.init>/bin/init", so give it
    # something real to point at rather than a dangling symlink. (Spelled
    # without braces on purpose: this is a shell comment inside a Nix
    # indented string, where a dollar-brace is still interpolated.)
    ln -s ../sbin/init "$out/bin/init"

    # /etc/default/init, which init reads through definit(3) for the initial
    # environment. Shipped rather than installed: upstream's `install` target
    # also deletes /etc/init and /usr/sbin/init compat links against a live
    # ROOT, which is not something to run here.
    cp init.dfl "$out/share/illumos/init.dfl"

    runHook postInstall
  '';

  meta.mainProgram = "init";
}
