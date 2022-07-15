## How to upgrade llvm_git
- Run `update-git.py`. This will set the github revision and sha256 for
  `llvmPackages_latest.llvm` to whatever the latest chromium build is using. For
  a more recent, commit run `nix-prefetch-github` and change the rev and sha256
  accordingly.
- That was the easy part. The hard part is updating the patch files. The general
  process is:
  1. try to build `llvmPackages_latest.llvm` and associated packages such as
     `clang` and `compiler-rt`. You can use the `-L` and `--keep-failed` flags to make
     debugging patch errors easy, e.g., `nix build .#llvmpackages_llvm -L --keep-failed`
  2. The build will error out with something similar to this:
     ```sh
     ...
     clang-unstable> patching sources
     clang-unstable> applying patch /nix/store/nndv6gq6w608n197fndvv5my4a5zg2qi-purity.patch
     clang-unstable> patching file lib/Driver/ToolChains/Gnu.cpp
     clang-unstable> Hunk #1 FAILED at 487.
     clang-unstable> 1 out of 1 hunk FAILED -- saving rejects to file lib/Driver/ToolChains/Gnu.cpp.rej
     note: keeping build directory '/tmp/nix-build-clang-unstable-2022-25-07.drv-17'
     error: builder for '/nix/store/zwi123kpkyz52fy7p6v23azixd807r8c-clang-unstable-2022-25-07.drv' failed with exit code 1;
            last 8 log lines:
            > unpacking sources
            > unpacking source archive /nix/store/mrxadx11wv1ckjr2208qgxp472pmmg6g-clang-src-unstable-2022-25-07
            > source root is clang-src-unstable-2022-25-07/clang
            > patching sources
            > applying patch /nix/store/nndv6gq6w608n197fndvv5my4a5zg2qi-purity.patch
            > patching file lib/Driver/ToolChains/Gnu.cpp
            > Hunk #1 FAILED at 487.
            > 1 out of 1 hunk FAILED -- saving rejects to file lib/Driver/ToolChains/Gnu.cpp.rej
            For full logs, run 'nix log /nix/store/zwi123kpkyz52fy7p6v23azixd807r8c-clang-unstable-2022-25-07.drv'.
     note: keeping build directory '/tmp/nix-build-compiler-rt-libc-unstable-2022-25-07.drv-20'
     error: 1 dependencies of derivation '/nix/store/ndbbh3wrl0l39b22azf46f1n7zlqwmag-clang-wrapper-unstable-2022-25-07.drv' failed to build
     ```

     Notice the `Hunk #1 Failed at 487` line. The lines above show us that the
     `purity.patch` failed on `lib/Driver/ToolChains/Gnu.cpp` when compiling `clang`.
 3. The task now is to cross reference the hunks in the purity patch with
    `lib/Driver/ToolCahins/Gnu.cpp.orig` to see why the patch failed. The
    `.orig` file will be in the build directory referenced in the line `note:
    keeping build directory ...`; this message results from the `--keep-failed`
    flag.
 4. Now you should be able to open whichever patch failed, and the `foo.orig`
    file that it failed on. Correct the patch by adapting it to the new code and
    be mindful of whitespace; which can be an easily missed reason for failures.
    For cases where the hunk is no longer needed you can simply remove it from
    the patch.

## gnu-install-dirs patches

### What
TODO

### Why 
TODO

### The plan
TODO
