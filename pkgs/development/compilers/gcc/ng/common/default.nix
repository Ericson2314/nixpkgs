{
  lib,
  newScope,
  stdenv,
  overrideCC,
  fetchgit,
  fetchurl,
  gitRelease ? null,
  officialRelease ? null,
  monorepoSrc ? null,
  version ? null,
  patchesFn ? lib.id,
  wrapCCWith,
  binutilsNoLibc,
  binutils,
  buildGccPackages,
  targetGccPackages,
  windows,
  makeScopeWithSplicing',
  otherSplices,
  ...
}@args:

assert lib.assertMsg (lib.xor (gitRelease != null) (officialRelease != null)) (
  "must specify `gitRelease` or `officialRelease`"
  + (lib.optionalString (gitRelease != null) " — not both")
);

let
  monorepoSrc' = monorepoSrc;

  # libgomp is OpenMP on top of pthreads, and will refuse to build with
  # any other threading model.
  hasLibgomp = targetGccPackages.libgcc.threadModel == "posix";

  libgompCflags = lib.optionals hasLibgomp [
    "-B${targetGccPackages.libgomp}/lib"
  ];
  libgompIncludeCflags = lib.optionals hasLibgomp [
    "-I${targetGccPackages.libgomp}/lib/gcc/${metadata.release_version}/include"
  ];

  metadata = rec {
    inherit
      (import ./common-let.nix {
        inherit (args)
          lib
          gitRelease
          officialRelease
          version
          ;
      })
      releaseInfo
      ;
    inherit (releaseInfo) release_version version;
    # A VCS checkout ships none of the generated sources (`gengtype-lex.cc` and
    # friends) that a release tarball does, so the components that need them
    # take `fromVCS` and add `flex`/`bison`. It follows from `gitRelease`
    # rather than being an argument of its own, so it cannot disagree with the
    # source it describes.
    fromVCS = gitRelease != null;
    inherit
      (import ./common-let.nix {
        inherit
          lib
          fetchgit
          fetchurl
          release_version
          gitRelease
          officialRelease
          monorepoSrc'
          version
          ;
      })
      gcc_meta
      monorepoSrc
      ;
    src = monorepoSrc;
    versionDir =
      (toString ../.) + "/${if (gitRelease != null) then "git" else lib.versions.major release_version}";
    getVersionFile =
      p:
      builtins.path {
        name = baseNameOf p;
        path =
          let
            patches = args.patchesFn (import ./patches.nix);

            constraints = patches."${p}" or null;
            matchConstraint =
              {
                before ? null,
                after ? null,
                path,
              }:
              let
                check = fn: value: if value == null then true else fn release_version value;
                matchBefore = check lib.versionOlder before;
                matchAfter = check lib.versionAtLeast after;
              in
              matchBefore && matchAfter;

            patchDir =
              toString
                (
                  if constraints == null then
                    { path = metadata.versionDir; }
                  else
                    (lib.findFirst matchConstraint { path = metadata.versionDir; } constraints)
                ).path;
          in
          "${patchDir}/${p}";
      };
  };
in
makeScopeWithSplicing' {
  inherit otherSplices;
  f =
    gccPackages:
    let
      callPackage = gccPackages.newScope (args // metadata);

      # Every compiler from the threaded `libgcc-libc` onwards has to be able
      # to find the threading library's headers and import library, since that
      # is what `gthr-default.h` includes and what libstdc++ and user code
      # link against. As with the runtime libraries, what belongs on a
      # compiler's search path is the *target* platform's build of it.
      threadsPackages = lib.optional (targetGccPackages.threads != null) targetGccPackages.threads;

      # `extraPackages` only reaches builds that go through a stdenv, whose
      # setup hooks put those directories on the search paths. Running the
      # wrapped compiler by hand gets nothing that way, and the first `#include
      # <thread>` then fails on the `mcfgthread` header. So name the
      # directories here as well, exactly as the runtime libraries are.
      threadsCflags = lib.optionals (targetGccPackages.threads != null) [
        "-B${targetGccPackages.threads}/lib"
        "-isystem ${lib.getDev targetGccPackages.threads}/include"
      ];

      # A gcc *configured* for a threading model links that model's library
      # through its own specs. Ours is configured independently of the
      # runtimes (see ../README.md), so it does not, and the flag has to come
      # from the wrapper instead — without it libstdc++ does not even link,
      # failing on undefined `__MCF_gthr_*`.
      #
      # This is a whole `nixSupport` fragment, rather than just the flag list,
      # because an empty `cc-ldflags` is not the same as none at all:
      # `cc-wrapper` writes the file either way, so naming the attribute
      # unconditionally would rebuild every wrapper on every platform.
      threadsNixSupport = lib.optionalAttrs ((targetGccPackages.threads.threadModel or null) == "mcf") {
        cc-ldflags = [ "-lmcfgthread" ];
      };
    in
    {
      # Where the libc's own threading is not the one we want, a separate
      # library supplies it. MinGW is the case in point: its libc offers only
      # the `win32` model, and `mcfgthreads` gives us `mcf`, which is what the
      # monolithic `gcc` picks there too (see `threadsCross`).
      #
      # `null` means "whatever the libc offers", which is the answer
      # everywhere else. The model itself is not written down here: the
      # package declares it, in the same `passthru.threadModel` a libc uses.
      #
      # Nothing needs doing to keep this out of the bootstrap cycle:
      # `windows.crossThreadsStdenv`, which is what this is built with, is
      # stage 3 of the chain on `useGccNG` platforms — real libc, bootstrap
      # single-threaded libgcc — which is exactly the compiler that goes on to
      # build the threaded `libgcc-libc`. A threading library is plain C and
      # needs no threading model of its own, so it does not mind.
      threads = if stdenv.hostPlatform.isMinGW then windows.mcfgthreads else null;

      stdenv = overrideCC stdenv gccPackages.gcc;

      gcc-unwrapped = callPackage ./gcc { };

      libiberty = callPackage ./libiberty { };
      # The other three static libraries `gcc/` links out of sibling build
      # directories. They are packages because the `gcc` component is built
      # without GCC's top level: see the boundary note in `./gcc`.
      libcpp = callPackage ./libcpp { };
      libdecnumber = callPackage ./libdecnumber { };
      libcody = callPackage ./libcody { };
      libsanitizer = callPackage ./libsanitizer { };
      libquadmath = callPackage ./libquadmath { };

      # THE TWO COMPONENTS THAT TURN A BACK END INTO A TARGET.
      #
      # `gcc-unwrapped` is one store path serving 47 back ends and naming no
      # target. Everything that depends on which assembler, linker and system
      # headers a particular machine has is asked here, per machine, after that
      # compiler is built -- and a wrapper composes the two into something a
      # user can call a cross compiler.
      #
      # Note where each sits in the build/host/target scheme, because it is the
      # answer to why they are separate:
      #
      #   `fixincludes` builds C and has a --host and NO target. One store path
      #     serves every target. (`fixincludes/configure.ac` says so where
      #     `ACX_NONCANONICAL_TARGET` used to be, and `Makefile.def` has never
      #     listed it as a `target_module`.)
      #   `target-specs` and `include-fixed` compile nothing at all. They are
      #     data about one machine, so they are instantiated once per machine --
      #     which in this package set means `stdenv.hostPlatform`, exactly as
      #     for `libgcc`.
      #
      # `gcc-unwrapped` comes from `buildGccPackages` HERE AND THAT IS NOT
      # PEDANTRY. What this reads out of it -- `multi-target.manifest` and the
      # source-derived spec halves -- is the same for every target, but the
      # derivation that carries it is per *host*. Left to the scope, a cross set
      # asked for a compiler that RUNS on the target: measured, it went off to
      # build `gcc-aarch64-unknown-linux-gnu-17.0.0` and died in that compiler's
      # own configure on `gmp.h`, an error naming nothing to do with specs.
      target-specs = callPackage ./target-specs {
        gcc-unwrapped = buildGccPackages.gcc-unwrapped;
        # `buildPackages.binutilsNoLibc`, AND EVERY PART OF THAT IS LOAD-BEARING.
        # Three other candidates were tried and each failed; the failures are
        # recorded because they are what stops the next person re-treading it.
        #
        # This used to read `stdenv.cc.bintools`, under a comment claiming
        # "`stdenv` here is still the outer one, before `overrideCC`". THAT
        # CLAIM WAS FALSE, and false on exactly the platforms this set is for:
        # `all-packages.nix:91-92` makes the top-level stdenv
        # `overrideCC stdenvNoCC buildPackages.gccNGPackages.gccNoLibgcc` when
        # `useGccNG` is set, so `stdenv.cc` IS the gcc-ng wrapper, which wraps
        # `gcc-composed`, which is built from `target-specs`. It evaluated
        # everywhere `useGccNG` was off, which is why the comment survived.
        #
        # What did not work:
        #
        #   `stdenv.cc.bintools`   -- the cycle above; `infinite recursion` at
        #       `target-specs/default.nix`'s `--with-tools-dir`.
        #   `binutils` / `binutilsNoLibc` (THIS scope's) -- infinite recursion
        #       one layer deeper. In a cross set those are the copies that RUN
        #       on the target, so their own `buildInputs` are target libraries,
        #       built with the gcc-ng stdenv: the same cycle by a longer route.
        #       The trace ends in `binutils-aarch64-unknown-linux-musl`'s
        #       `buildInputs`.
        #   `buildPackages.binutils` -- infinite recursion again, and this is
        #       the SECOND cycle, through the bintools wrapper's `libc`, since
        #       the target libc is built with the gcc-ng stdenv.
        #
        # `buildPackages.binutilsNoLibc` is right on both axes.
        # `buildPackages.targetPlatform == hostPlatform` is a nixpkgs
        # invariant, so it runs on the build machine and emits for this target
        # -- its `bin` holds the `<triple>-as` and `<triple>-ld` that
        # `target-specs` looks for -- and `NoLibc` breaks the second cycle,
        # which is the case that package exists for.
        #
        # DROPPING THE LIBC COSTS NOTHING HERE, AND THAT IS MEASURED RATHER
        # THAN HOPED. Several of these probes link, and a probe that cannot
        # link records "no" exactly as a real "no" does, so a quietly
        # pessimistic spec file was the thing to rule out. Running the identical
        # probe for `aarch64-unknown-linux-gnu` against the with-libc and the
        # no-libc wrapper gives `specs-config` files that are byte-identical --
        # **0** differing lines -- and `specs` files differing only in the two
        # embedded paths naming their own output directories.
        bintools = args.buildPackages.binutilsNoLibc;
      };

      # The join, and the thing every wrapper below should really be wrapping:
      # the target-agnostic compiler plus THIS target's probed spec file, in one
      # prefix. `gcc-unwrapped` on its own cannot compile for any target at all
      # -- it exits with `no configuration file for target ...` before reaching
      # cc1 -- so a wrapper built straight on it is a compiler that names a
      # target and cannot serve it.
      #
      # The two halves come from two different sets, and that is the whole
      # point: `gcc-unwrapped` is a property of the machine this compiler RUNS
      # on, `target-specs` of the machine it SERVES. Taking both from one set
      # produced a cross wrapper carrying x86_64's spec file with aarch64's
      # bintools, and the driver's own diagnostic named two paths under an
      # x86_64 prefix -- correct, and unreadable as a cause.
      gcc-composed = callPackage ./gcc-composed {
        gcc-unwrapped = buildGccPackages.gcc-unwrapped;
        target-specs = targetGccPackages.target-specs;
      };

      # `fixincludes` runs on the build machine, so it is taken from
      # `buildGccPackages` at the use site rather than being a host package
      # here; this attribute is the one that runs on THIS platform, for a set
      # that is being cross-built for it.
      fixincludes = callPackage ./fixincludes {
        libiberty = gccPackages.libiberty;
      };

      # The per-target application of it. `cc` is the compiler that will
      # preprocess for this target: `mkheaders` needs its predefined macros and
      # refuses to run without them.
      include-fixed = callPackage ./include-fixed {
        fixincludes = buildGccPackages.fixincludes;
        # Same reason as for `target-specs` above: the halves of `install-tools`
        # this reads are host-independent data, but the derivation carrying them
        # runs on the build machine.
        gcc-unwrapped = buildGccPackages.gcc-unwrapped;
      };

      gfortran-unwrapped = gccPackages.gcc-unwrapped.override {
        stdenv = overrideCC stdenv buildGccPackages.gcc;
        langFortran = true;
      };

      gfortran = wrapCCWith {
        cc = gccPackages.gfortran-unwrapped;
        libcxx = targetGccPackages.libstdcxx;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc
        ]
        ++ threadsPackages;
        nixSupport = threadsNixSupport // {
          cc-cflags = [
            "-B${targetGccPackages.libgcc}/lib"
            "-B${targetGccPackages.libssp}/lib"
            "-B${targetGccPackages.libatomic}/lib"
          ]
          ++ libgompCflags
          ++ [
            "-B${targetGccPackages.libstdcxx}/lib"
            "-B${targetGccPackages.libgfortran}/lib/"
          ]
          ++ threadsCflags;
        };
      };

      gfortranNoLibgfortran = wrapCCWith {
        cc = gccPackages.gfortran-unwrapped;
        libcxx = targetGccPackages.libstdcxx;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc
        ]
        ++ threadsPackages;
        nixSupport = threadsNixSupport // {
          cc-cflags = [
            "-B${targetGccPackages.libgcc}/lib"
            "-B${targetGccPackages.libssp}/lib"
            "-B${targetGccPackages.libatomic}/lib"
          ]
          ++ libgompCflags
          ++ libgompIncludeCflags
          ++ threadsCflags;
        };
      };

      gcc = wrapCCWith {
        cc = gccPackages.gcc-composed;
        libcxx = targetGccPackages.libstdcxx;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc
        ]
        ++ threadsPackages;
        nixSupport = threadsNixSupport // {
          cc-cflags = [
            "-B${targetGccPackages.libgcc}/lib"
            "-B${targetGccPackages.libssp}/lib"
            "-B${targetGccPackages.libatomic}/lib"
          ]
          ++ libgompCflags
          ++ [
            # `libcxx` above tells cc-wrapper where the C++ *headers* are; it does
            # not put the library itself on the link path for a GNU compiler. So
            # every C++ link failed with `cannot find -lstdc++` until this was
            # added, in the same style as the other runtime libraries.
            "-B${targetGccPackages.libstdcxx}/lib"
          ]
          ++ libgompIncludeCflags
          ++ threadsCflags;
        };
      };

      # Stage 1 of the bootstrap chain; see ../README.md.
      #
      # No `libc` is passed: `wrapCCWith` defaults it to `bintools.libc`, and
      # `binutilsNoLibc` carries `preLibcHeaders`. That is the only place the
      # pre-libc stage is written down.
      gccNoLibgcc = wrapCCWith {
        cc = gccPackages.gcc-composed;
        libcxx = null;
        bintools = args.buildPackages.binutils;
        extraPackages = [ ];
        nixSupport.cc-cflags = [
          "-nostartfiles"
        ];
      };

      # Built before there is a libc, and not intended for use beyond getting
      # one built. Note the two differ only by `stdenv`: which stage this is
      # follows from the compiler, never from an argument.
      libgcc-no-libc = callPackage ./libgcc {
        stdenv = overrideCC stdenv buildGccPackages.gccNoLibgcc;
        # The bootstrap libgcc predates the threading library, so it gets no
        # threads at all. Spelled out because `callPackage` would otherwise
        # fill the argument in from the set's own `threads`.
        threads = null;
      };

      # The real one, built against the finished libc, so it can use that
      # libc's threads — or the separate threading library where we have asked
      # for one. This is what everything above the libc gets.
      libgcc-libc = callPackage ./libgcc {
        stdenv = overrideCC stdenv buildGccPackages.gccWithLibcAndBasicLibgcc;
        # Spelled out for the same reason as the `null` above, and so that it
        # is this set's own answer rather than anything `callPackage` might
        # find under that name.
        inherit (gccPackages) threads;
      };

      libgcc =
        if stdenv.hostPlatform.libc == null then gccPackages.libgcc-no-libc else gccPackages.libgcc-libc;

      # Stage 2: libgcc available, libc not yet — what compiling a libc needs.
      # `binutilsNoLibc` is what keeps the libc out, so nothing here refers to
      # a libc derivation and the cycle stays broken.
      gccWithLibgccNoCxx = wrapCCWith {
        cc = gccPackages.gcc-composed;
        libcxx = null;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc-no-libc
        ];
        nixSupport.cc-cflags = [
          "-B${targetGccPackages.libgcc-no-libc}/lib"
        ];
      };

      # Freestanding libstdc++ not depending on any libc
      libstdcxx-no-libc = callPackage ./libstdcxx {
        stdenv = overrideCC stdenv buildGccPackages.gccWithLibgccNoCxx;
        # The set's plain `libgcc` is the finished one, which is built after
        # the libc; only the bootstrap libgcc exists this early.
        libgcc = gccPackages.libgcc-no-libc;
      };

      gccWithLibgcc =
        # Cygwin's libc is in partly C++ and needs C++ headers to build.
        if stdenv.targetPlatform.isCygwin then
          wrapCCWith {
            cc = gccPackages.gcc-composed;
            libcxx = targetGccPackages.libstdcxx-no-libc;
            bintools = binutilsNoLibc;
            extraPackages = [
              targetGccPackages.libgcc-no-libc
            ];
            nixSupport.cc-cflags = [
              "-B${targetGccPackages.libgcc-no-libc}/lib"
              # See above for why `libcxx = ...` is not enough.
              "-B${targetGccPackages.libstdcxx-no-libc}/lib"
            ];
          }
        else
          gccPackages.gccWithLibgccNoCxx;

      # Stage 3: real libc, bootstrap libgcc still. The finished libgcc is what
      # this is about to build.
      gccWithLibcAndBasicLibgcc = wrapCCWith {
        cc = gccPackages.gcc-composed;
        libcxx = null;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc-no-libc
        ];
        nixSupport.cc-cflags = [
          "-B${targetGccPackages.libgcc-no-libc}/lib"
        ];
      };

      gccWithLibc = wrapCCWith {
        cc = gccPackages.gcc-composed;
        libcxx = null;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc
        ]
        ++ threadsPackages;
        nixSupport = threadsNixSupport // {
          cc-cflags = [
            "-B${targetGccPackages.libgcc}/lib"
          ]
          ++ threadsCflags;
        };
      };

      libssp = callPackage ./libssp {
        stdenv = overrideCC stdenv buildGccPackages.gccWithLibc;
      };

      gccWithLibssp = wrapCCWith {
        cc = gccPackages.gcc-composed;
        libcxx = null;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc
        ]
        ++ threadsPackages;
        nixSupport = threadsNixSupport // {
          cc-cflags = [
            "-B${targetGccPackages.libgcc}/lib"
            "-B${targetGccPackages.libssp}/lib"
          ]
          ++ threadsCflags;
        };
      };

      libatomic = callPackage ./libatomic {
        stdenv = overrideCC stdenv buildGccPackages.gccWithLibssp;
      };

      gccWithLibatomic = wrapCCWith {
        cc = gccPackages.gcc-composed;
        libcxx = null;
        bintools = args.buildPackages.binutils;
        extraPackages = [
          targetGccPackages.libgcc
        ]
        ++ threadsPackages;
        nixSupport = threadsNixSupport // {
          cc-cflags = [
            "-B${targetGccPackages.libgcc}/lib"
            "-B${targetGccPackages.libssp}/lib"
            "-B${targetGccPackages.libatomic}/lib"
          ]
          ++ threadsCflags;
        };
      };

      libgfortran = callPackage ./libgfortran {
        stdenv = overrideCC stdenv buildGccPackages.gcc;
        gfortran = buildGccPackages.gfortranNoLibgfortran;
      };

      libstdcxx = callPackage ./libstdcxx {
        stdenv = overrideCC stdenv buildGccPackages.gccWithLibatomic;
      };

      libgomp = callPackage ./libgomp {
        stdenv = overrideCC stdenv buildGccPackages.gccWithLibatomic;
      };
    };
}
