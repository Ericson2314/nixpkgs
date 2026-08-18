{
  lib,
  mkDerivation,

  cw,
  buildPackages,
  headers,

  librpcsvc,
  libnsl,
  libsocket,
  libscf,
}:

# mount(8) for NFS -- usr/src/cmd/fs.d/nfs/mount, installed as
# /usr/lib/fs/nfs/mount, which is what the generic mount(8) dispatcher execs
# for `-F nfs`.
#
# This is the point of the NFS work: with it, /nix/store can be mounted
# read-only from the host instead of being materialised into a UFS image at
# every build and copied into RAM at every boot. Those are two halves of one
# cost -- ~986MB of GRUB copying before the kernel starts, and tens of
# gigabytes of accumulated images on the host.
#
# Packaged rather than hand-rolled the way `setaddr` was, because it is a real
# program: it parses host:path, resolves the server, negotiates the version and
# assembles the `nfs_args` the kernel wants, netbuf address and knetconfig
# included. That is not a short program to write for NFSv4.
#
#     mount -F nfs -o vers=4,proto=tcp,port=NNNNN,ro 10.0.2.2:/store /nix/store
mkDerivation {
  pname = "mount-nfs";
  path = "usr/src/cmd/fs.d/nfs/mount";

  extraPaths = [
    "usr/src/Makefile.master"
    "usr/src/Makefile.master.64"
    "usr/src/Makefile.native"
    "usr/src/Makefile.smatch"

    "usr/src/cmd/Makefile.cmd"
    "usr/src/cmd/Makefile.cmd.64"
    "usr/src/cmd/Makefile.ctf"
    "usr/src/cmd/Makefile.targ"

    # fslib.c is compiled straight into the program rather than linked from a
    # library (Makefile.mount's COMMONOBJ), so its source has to be here --
    # mount-ufs.nix needs the same.
    "usr/src/cmd/fs.d/Makefile.fstype"
    "usr/src/cmd/fs.d/Makefile.mount"
    "usr/src/cmd/fs.d/Makefile.mount.targ"
    "usr/src/cmd/fs.d/fslib.c"
    "usr/src/cmd/fs.d/fslib.h"

    # ../lib/nfs_sec.c and ../lib/replica.c are in SRCS, plus the nfs
    # subdirectory's own shared makefile fragment.
    "usr/src/cmd/fs.d/nfs/lib"
    "usr/src/cmd/fs.d/nfs/Makefile"
  ];

  # rpcgen: webnfs.h and webnfs_xdr.c are generated from webnfs.x at build
  # time. It comes from buildPackages.netbsd, since this package set has none
  # of its own, and needs a *traditional* cpp -- without RPCGEN_CPP it emits
  # only boilerplate and still exits 0, so the failure surfaces much later as
  # missing symbols. head.nix and librpcsvc.nix carry the same warning.
  extraNativeBuildInputs = [
    cw
    buildPackages.netbsd.rpcgen
  ];

  env.RPCGEN_CPP = buildPackages.writeShellScript "rpcgen-cpp" ''
    exec ${buildPackages.stdenv.cc}/bin/cpp -traditional-cpp -U__STDC__ "$@"
  '';

  buildInputs = [
    headers
    librpcsvc
    libnsl
    libsocket
    libscf
  ];

  # mount.c includes <libshare.h> for exactly one thing: `SA_OK`, which is
  # `#define SA_OK 0` and is what it compares nfs_smf_get_prop()'s return
  # against. `-lshare` is *not* in LDLIBS, so nothing links against libshare --
  # but libshare.h includes libzfs.h, which includes libzfs_core.h, and the
  # chain keeps going. Following it would drag the whole ZFS header tree in for
  # a macro that expands to zero.
  #
  # So drop the include and supply the macro on the command line. If this
  # program ever starts using libshare for real, it fails loudly here rather
  # than silently doing the wrong thing.
  # ...and both mount.c and ../lib/smfcfg.h include it, so a shim header on
  # the include path is cleaner than patching each includer. It supplies the
  # one macro and nothing else, which means any *other* use of libshare would
  # fail to compile here rather than silently pick up a stub.
  preBuild = ''
        mkdir -p shim
        cat > shim/libshare.h <<'SHIM'
        /*
         * Minimal stand-in for <libshare.h>; see mount-nfs.nix.
         *
         * cmd/fs.d/nfs/mount uses exactly one thing from the real header, the
         * SA_OK return code, and does not link -lshare. The real header pulls in
         * libzfs.h -> libzfs_core.h -> ..., i.e. the entire ZFS header tree, for
         * a macro that expands to zero.
         */
        #ifndef _LIBSHARE_H_SHIM
        #define _LIBSHARE_H_SHIM
        #define SA_OK 0
        #define SA_BAD_VALUE 15
        #endif
    SHIM
        sed -i 's/^    //' shim/libshare.h

        makeFlagsArray+=("CPPFLAGS.first=-I${headers}/include -I$PWD/shim")
  '';

  makeFlags = [
    # 64-bit, as everything here is. This directory has no amd64 subdirectory,
    # so upstream builds it 32-bit and the macros Makefile.cmd.64 would have
    # set are passed here instead; see mount-ufs.nix for the full account.
    "CFLAGS=$(CFLAGS64)"
    "ASFLAGS=$(ASFLAGS64)"
    "COMPILE.c=$(COMPILE64.c)"
    "LINK.c=$(LINK64.c)"
    "LDLIBS.cmd=$(LDLIBS64)"
    "MAPFILECLASS=-64"

    # Makefile.cmd pins the 32-bit interpreter on anything installed into the
    # root filesystem, which for a 64-bit build names an interpreter that does
    # not exist -- the kernel then kills the process with no output at all.
    # Same trap as mount-ufs.
    "64ONLY=$(POUND_SIGN)"

    "POST_PROCESS=:"
    "POST_PROCESS_O=:"

    "LDFLAGS.cmd="
    "LDCHECKS="
  ];

  # webnfs_client.c is *generated* -- rpcgen -l from webnfs.x -- and NetBSD's
  # rpcgen emits the CLNT_CALL stubs without the (xdrproc_t) casts illumos'
  # own puts there:
  #
  #     webnfs_client.c:23: error: passing argument 4 of
  #         'clnt->cl_ops->cl_call' from incompatible pointer type
  #
  # There is no source to fix: the file does not exist in the tree. The stubs
  # are semantically right -- an xdr_*() function passed where xdrproc_t is
  # wanted, which is what the cast would say -- so demote the diagnostic
  # rather than post-processing generated code. GCC 14 made this an error by
  # default; it was a warning for the whole life of this code.
  #
  # Scoped to this package, and only because the generator is foreign. This
  # belongs with the rest of the foreign-host build support.
  env.NIX_CFLAGS_COMPILE = "-Wno-incompatible-pointer-types";

  buildFlags = [ "all" ];

  installPhase = ''
    runHook preInstall

  ''
  # Upstream's path for the fstype-specific program, so a generic mount(8)
  # finds it if one is packaged later.
  + ''
    mkdir -p $out/lib/fs/nfs
    cp mount $out/lib/fs/nfs/mount
    chmod 755 $out/lib/fs/nfs/mount

    runHook postInstall
  '';

  meta = {
    description = "illumos NFS mount(8), for /usr/lib/fs/nfs/mount";
  };
}
