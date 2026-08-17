# GCC Next-Generation

Experimental split GCC package set, based on the LLVM package set design.

The monolithic `gcc` derivation builds the compiler and every runtime library in one go, so a change to the target libc rebuilds the compiler too.
This set separates them — `gcc`, `libgcc`, `libstdcxx` and the rest are individual packages — so the compiler stops depending on the libc, and each piece can be rebuilt on its own.
That someday has arrived: this set builds the `multi-target-0` branch, where 47 back ends link into one `cc1` and the compiler carries no target of its own.
`gcc-unwrapped` is a single derivation with a single store path, shared by every target — measured by `mt-compare.nix` at the repository root, which asks three different cross package sets for it and compares.
What used to be "rebuild the compiler per target" is now "one compiler, N wrappers": the per-target facts belong to the wrapper that composes a target out of the compiler, that target's spec file, its libc and its binutils.
The next section says which derivations those are; they exist now rather than being planned.

A platform opts in with `useGccNG`, in the same way it would opt into `useLLVM`.

## How a target gets made

`gcc-unwrapped` ships **back ends**. It cannot compile for any of them:

```
$ aarch64-unknown-linux-gnu-gcc -S t.c
fatal error: no configuration file for target `aarch64-unknown-linux-gnu'.
  Looked in: .../lib/gcc/17.0.0/aarch64-unknown-linux-gnu/specs-config
```

A **target** is composed, out of four derivations, and each of them is
per-target except the first:

| derivation | one per | what it is |
|---|---|---|
| `gcc-unwrapped` | host | 47 back ends, one store path, no target |
| `target-specs` | target | that target's spec file and capability config, from probing its *actual* assembler and linker |
| `fixincludes` | host | `fixincl`, `fixinc.sh`, `mkheaders` — a `--host` and no target |
| `include-fixed` | target | runs `mkheaders <target>` to fix *that* target's system headers |
| `gcc-composed` | target | the join: `gcc-unwrapped` + that target's `specs-config`, in one prefix |

`gcc-composed` is what every `wrapCCWith` in the set wraps, and it is **not** a
`symlinkJoin`. `find_target_config` (`gcc/gcc.cc:8694`) searches
`$GCC_EXEC_PREFIX`, then the prefix implied by where the driver binary *really*
is, then the configured-in one — so a symlinked driver sends it looking in
`gcc-unwrapped`'s prefix, and `GCC_EXEC_PREFIX` cannot be used because it
redirects the `cc1` search too. Copying the driver binaries and symlinking the
rest is what works, and the derivation checks it by asking the driver
(`-dumpspecs`) rather than by checking that the files were placed.

`target-specs` must be given the target's real binutils. Without them its
configure writes **no file at all** and exits 0 (`skipping ...: target tools
unavailable, nothing probed`), which is why the derivation checks for the file
rather than the status.

## The bootstrap chain

The libc and libgcc depend on each other: a libc's own sources call into libgcc for integer and floating-point helpers and for stack unwinding, and a libgcc that can use the libc's threads needs the libc.

The way out we currently use is the same one the LLVM set takes with `compiler-rt-no-libc` and `compiler-rt-libc` — build the runtime twice, either side of the libc.
It is unclear whether this works in general to resolve the circularity, but we shall see.

That gives four compilers, each one step further along:

| compiler | libc | libgcc | used to build |
|---|---|---|---|
| `gccNoLibgcc` | headers, or nothing | — | `libgcc-no-libc` |
| `gccWithLibgcc` | headers, or nothing | `libgcc-no-libc` | the libc |
| `gccWithLibcAndBasicLibgcc` | real | `libgcc-no-libc` | `libgcc-libc` |
| `gccWithLibc` / `gcc` | real | `libgcc-libc` | everything else |

`libgcc` resolves to `libgcc-libc` wherever a libc exists; only those first three stages ever see `libgcc-no-libc`.
The bootstrap one is single-threaded and compiled against the libc's headers at best, so it is not intended for use beyond building the libc.

Nothing is passed down to say which stage is which.
It follows from the compiler: each package reads `stdenv.cc.libc` and needs no flag of its own.
That is also how the two `libgcc`s differ — same expression, different `stdenv`.

## Where the pre-libc stage is written down

`binutilsNoLibc` carries `preLibcHeaders` as its `libc`: the header-only stand-in for platforms that have one, and nothing at all for platforms that do not.
`wrapCCWith` defaults `libc` to `bintools.libc`, so the bootstrap compilers inherit it, and everything built with them reads `stdenv.cc.libc`.

This used to say that a sysroot had to be set as well, because `gcc/configure` took `target_header_dir` from `--with-sysroot` and `target_header_dir` decided `inhibit_libc`.
That is now history: `target_header_dir` is **gone** on the branch — `gcc/configure.ac:2197` reads `dnl target_header_dir is GONE.` and is the file's only occurrence — so `--with-sysroot=` and `--with-native-system-header-dir=` were inert in the `libgcc` derivation and have been removed from it.

The thing that paragraph was protecting against is still real, and is now asserted rather than inferred.
`inhibit_libc` is passed explicitly (`inhibit_libc=true|false`, from whether the compiler has a libc at all), and a libgcc built with it still compiles, links and installs **with the same file names**, just with split-stack, most of libgcov and the `dl_iterate_phdr` FDE lookup missing.
So the build checks the symbols: a libgcc built against a real libc must contain `__splitstack_*`, `__gcov_*` and the `dip` unwinder path, and the pre-libc one must not.

## Threading

The threading model comes from whatever provides the threads, which declares it as `passthru.threadModel`; `libgcc` reads it from there, and `libstdcxx` takes both the model and the generated `gthr-default.h` from `libgcc`.

Usually that is the libc.
Where the libc's own threading is not what we want, a separate library supplies it, and `libgcc` is given it as the `threads` argument, which takes precedence.
MinGW is the case in point: its libc offers only `win32`, so we build against `windows.mcfgthreads` and get `mcf`, the same choice the monolithic `gcc` makes through `threadsCross`.
Unlike `threadsCross`, the model is not spelled out at the use site — the package declares its own, exactly as a libc does.

That library is built with `windows.crossThreadsStdenv`, which on a `useGccNG` platform is stage 3 of the bootstrap chain — the same compiler that then builds the threaded `libgcc`.
Being plain C with no threading model of its own, it does not mind that stage 3's libgcc has none, and that is what keeps the arrangement from being circular.

Reading it from the compiler instead, with `$CC -v | sed -n 's/^Thread model: //p'`, reports the wrong component: in this set the compiler is configured separately from libgcc, so the two can disagree.
A platform with nothing to declare a model gets `single`.

## Relationship to the monolithic set

Both are packaged from the same sources and, for now, the same version: `gccNGPackages` tracks `default-gcc-version` with no fallback, so bumping the monolithic default past what is packaged here is an evaluation error rather than a silent version skew.

Nothing selects GGN NG yet by default.
The plan is for very exotic package sets to switch to this first.
The main tier-1 native Linux package sets cached on `cache.nixos.org` will come later.
