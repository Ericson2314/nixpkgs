{
  buildPackages,
  mkDerivation,

  illumosSetupHook,
  make,
  install,
  cw,
  ld-native,

  sgs-ld,
  sgs-libconv,
  sgs-liblddbg,
  sgs-librtld,
  sgs-libld,
  sgs-libelf,

  crt,
  headers,
  libcMinimal,
}:

# ld.so.1, the illumos runtime linker. Every dynamic illumos binary names it in
# PT_INTERP (/lib/amd64/ld.so.1 for us), and illumos has no static libc, so
# nothing runs without it.
#
# cmd/sgs/rtld/Makefile.com links it against libconv (a PIC archive), libc_pic.a
# and the shared liblddbg/librtld/libld. The three shared ones are lazily
# dlopen()ed at run time -- for LD_DEBUG, dldump(3C) and configuration files
# respectively -- but ld.so.1 references their symbols directly, so they have to
# exist at link time. `-z ignore` (cmd/sgs/Makefile.com:70) then keeps them out
# of the final dynamic section.

mkDerivation {
  libcMinimal = true;
  path = "usr/src/cmd/sgs/rtld/amd64";
  pname = "rtld";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/lib/Makefile.lib"
    "usr/src/lib/Makefile.lib.64"
    "usr/src/lib/Makefile.targ"
    "usr/src/lib/Makefile.rootfs"

    "usr/src/cmd/sgs/Makefile.com"
    "usr/src/cmd/sgs/rtld"
    "usr/src/cmd/sgs/include"
    "usr/src/cmd/sgs/messages"
    # SGSCOMMONOBJ = alist.o strhash.o.
    "usr/src/cmd/sgs/common"

    # AVLOBJ and DTROBJ are compiled straight out of usr/src/common.
    "usr/src/common/avl"
    "usr/src/common/dtrace"
    "usr/src/common/elfcap"
    "usr/src/common/sgsrtcid"
    "usr/src/common/mapfiles"

    # G_MACHOBJS = doreloc.o, the relocation engine shared with krtld, plus the
    # PLAT include directory (Makefile.com:54-57, 90-96).
    "usr/src/uts/common/krtld"
    "usr/src/uts/intel/amd64"

    # amd64/Makefile:52 sets CRTSRCS = ../../../../lib/crt/amd64; crti.o and
    # crtn.o are compiled from there rather than taken from the crt package.
    "usr/src/lib/crt"

    "usr/src/lib/libc/inc"
  ];

  nativeBuildInputs = [
    illumosSetupHook
    make
    install
    cw
    ld-native
    (buildPackages.writeShellScriptBin "arch" "echo i386")
    (buildPackages.writeShellScriptBin "mach" "echo i386")
  ];

  buildInputs = [
    headers
    crt
    libcMinimal
  ];

  env.NIX_CFLAGS_COMPILE = builtins.toString [
    "-B${crt}/lib"
    "-Wno-error"
  ];

  # cmd/sgs/rtld/Makefile.com:159-173 sets STACKPROTECT = none, because ld.so.1
  # runs before libc has set the guard value up. That only clears illumos' own
  # flag -- the nixpkgs cc wrapper adds -fstack-protector-strong of its own
  # accord, and the resulting references to __stack_chk_fail pull
  # libc_pic.a(ssp.o) into the link. ssp.o needs gethrtime, which needs the
  # POSIX timers, which need the whole thread library, and the link then dies
  # on ~40 multiply-defined symbols because rtld has its own read(), malloc(),
  # printf() and mutex_lock().
  hardeningDisable = [ "stackprotector" ];

  # amd64/Makefile has `all: $(RTLD)` but Makefile.targ introduces explicit
  # targets before it, so name the goal rather than trusting dmake's default.
  buildFlags = [ "all" ];

  makeFlags = [
    "MCS=:"
    "POST_PROCESS_O=:"
    "POST_PROCESS_S_O=:"
    "POST_PROCESS_SO=:"
    "LDFLAGS.native="
    "CPPFLAGS.first=-I${headers}/include"
    "MACH=i386"
    "MACH64=amd64"
    "ONBLD_TOOLS=${buildPackages.illumos.ld-native}"

    # Makefile.com resolves each of these to a sibling build directory in the
    # source tree ($(SGSHOME)/libconv/$(MACH64), ../../libld/$(MACH64), ...).
    # Point them at the separately built packages instead. These are macros
    # given on the command line, so they also win over the reassignments in
    # amd64/Makefile:72-77.
    "CONVLIBDIR=-L${sgs-libconv}/lib"
    "CONVLIBDIR64=-L${sgs-libconv}/lib"
    "LDDBGLIBDIR=-L${sgs-liblddbg}/lib"
    "LDDBGLIBDIR64=-L${sgs-liblddbg}/lib"
    "RTLDLIB=-L${sgs-librtld}/lib"
    # $(CLIB) is -lc_pic, and libcMinimal installs libc_pic.a.
    "CPICLIB=-L${libcMinimal}/lib"
    "CPICLIB64=-L${libcMinimal}/lib"

    # rtld/Makefile.targ:75 already invokes $(LD) directly, so no BUILD.SO
    # override is needed here -- but DYNFLAGS still carries -Wl, prefixes from
    # lib/Makefile.lib, which sgs-ld strips.
    "LD=${sgs-ld}"
  ];

  # librtld.so.1 and libld.so.4 both record libelf.so.1 as NEEDED, so ld has to
  # be able to find it while resolving them -- even though ld.so.1 itself never
  # refers to libelf. $(LDLIB) is the last -L in LDLIBS; carrying the extra
  # directory there keeps it out of the way of everything else. It has to go
  # through makeFlagsArray rather than makeFlags because it contains a space.
  preBuild = ''
    makeFlagsArray+=("LDLIB=-L${sgs-libld}/lib -L${sgs-libelf}/lib")
  '';

  # Without this, nothing dynamically linked can be exec'd at all -- and the
  # failure is close to undebuggable.
  #
  # ld.so.1 carries a PT_SUNWDTRACE program header, built by libld from the
  # symbol named by -zdtrace=dtrace_data (cmd/sgs/rtld/Makefile.com:122):
  #
  #     phdr->p_vaddr = sdp->sd_sym->st_value;   /* update.c:4467 */
  #     phdr->p_memsz = sdp->sd_sym->st_size;
  #
  # GNU strip rewrites the file rather than editing it in place, and in doing so
  # zeroes that header's p_memsz -- PT_SUNWDTRACE is an OS-specific segment type
  # it has no handling for. libld gets it right; strip undoes it.
  #
  # The kernel then refuses every binary that names this interpreter:
  # dtrace_safe_phdr() (uts/common/exec/elf/elf.c:123) requires p_memsz >=
  # PT_SUNWDTRACE_SIZE, 64 on amd64. Worse, it fails *past the point of no
  # return* in elfexec(), so the process is SIGKILLed rather than given an
  # errno, and the only diagnostic -- "Bad DTrace phdr in ..." -- goes through
  # uprintf(), which logs SL_LOGONLY and so needs a syslogd to be seen.
  #
  # This is the same class of hazard as the kernel's own STRIP_STABS=: (see
  # unix.nix): GNU strip does not preserve illumos-specific ELF structure.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    # SONAME (amd64/Makefile:68) is /lib/amd64/ld.so.1, and that is also where
    # PT_INTERP points, so mirror the illumos layout under $out.
    mkdir -p "$out/lib/amd64"
    cp ld.so.1 "$out/lib/amd64/"

    runHook postInstall
  '';
}
