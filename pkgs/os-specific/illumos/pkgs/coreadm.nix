{
  mkDerivation,

  cw,
  headers,

  libproc,
  libscf,

  # libproc.h line 53 includes <libctf.h>, so libctf is a header dependency of
  # every libproc consumer, not just of libproc itself.
  libctf,
}:

# coreadm(8) -- usr/src/cmd/coreadm. Sets the system's core-dump policy.
#
# Packaged for one specific reason: without it, a crashing daemon can take the
# whole machine down. The root filesystem here is a ramdisk of a few hundred
# megabytes, and illumos' default per-process policy writes a full core named
# `core` into the process's current directory -- which for an SMF service is
# `/`. A daemon that crashes in a loop therefore fills the root filesystem:
#
#     NOTICE: alloc: /: file system full
#
# after which sshd starts dying mid-session, and the symptom (ssh drops) looks
# nothing like the cause (some unrelated daemon crashing). That is exactly how
# it was found -- see the note in nixbsd's core-dump activation script.
#
# The policy is a property of the running kernel, not of a file: `coreadm -d`
# takes effect immediately, and only `coreadm -u` consults
# /etc/coreadm.conf. So this is run from an activation script rather than
# staged as configuration.
mkDerivation {
  pname = "coreadm";
  path = "usr/src/cmd/coreadm";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # $(MAPFILE.NES), $(MAPFILE.PGA) and $(MAPFILE.NED) -- the non-executable
    # stack/data and page-alignment mapfiles Makefile.cmd puts on every command
    # through $(LDFLAGS.cmd). GNU ld read -M as "write a link map" and never
    # opened them; illumos ld does, and stops if they are not there.
    "usr/src/common/mapfiles"
  ];

  extraNativeBuildInputs = [ cw ];

  buildInputs = [
    headers
    libproc
    libscf
    libctf
  ];

  makeFlags = [
    # 64-bit, as everything in this package set is. cmd/coreadm has no amd64
    # subdirectory, so upstream builds it 32-bit and we pass what
    # Makefile.cmd.64 would have set. See mount-ufs.nix for the full account.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # coreadm installs through $(ROOTPROG), making it a $(ROOTFS_PROG) and so
    # subject to Makefile.cmd's 32-bit interpreter pin. Same trap, same remedy
    # as mount-ufs and dlmgmtd.
    "64ONLY=$(POUND_SIGN)"

    "POST_PROCESS=:"
    "POST_PROCESS_O=:"
    "CTFCONVERT_HOOK="
    "CTFMERGE_HOOK="
    "CTF_FLAGS="

    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # `all`, not `install`: the install target also wants $(ROOTMANIFEST) under
  # $(ROOTSVCSYSTEM), which is more of upstream's layout than belongs in a
  # store path. The manifest is placed by hand below for a configuration that
  # wants to run this under SMF.
  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp coreadm $out/bin/coreadm
    chmod 755 $out/bin/coreadm

    mkdir -p $out/lib/svc/manifest/system
    cp coreadm.xml $out/lib/svc/manifest/system/coreadm.xml

    runHook postInstall
  '';

  meta = {
    description = "illumos core file administration";
    mainProgram = "coreadm";
  };
}
