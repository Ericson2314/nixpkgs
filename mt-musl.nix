# THE musl ARM, AS AN OVERRIDE RATHER THAN AN EXTENSION.
#
# `gcc/configure` refuses `aarch64-unknown-linux-musl` and
# `aarch64-unknown-linux-gnu` in one back-end list -- `tm-aarch64.h` is
# generated once per BACK END from whichever is seen first, so the second would
# be built against the first`s ABI defaults with no diagnostic. See the long
# note at `enableBackends` in `pkgs/development/compilers/gcc/ng/common/gcc`.
#
# So a musl target means a DIFFERENT compiler, not a bigger one: this file
# substitutes musl for gnu in the 47-triple list and is therefore a second
# `gcc-unwrapped` store path. That is the honest shape of the limitation, and
# keeping it as a file rather than a shell one-liner is what makes it
# reproducible.
#
#     nix-build mt-musl.nix -A gccNGPackages_17.libgcc-no-libc
#     nix-build mt-musl.nix -A zlib

# The musl arm. `aarch64-unknown-linux-musl` REPLACES `aarch64-unknown-linux-gnu`
# in the back-end list rather than joining it: gcc/configure refuses two triples
# of one back end. Same substitution upstream measured.
import ./. {
  crossSystem = { config = "aarch64-unknown-linux-musl"; useGccNG = true; };
  overlays = [
    (final: prev: {
      gccNGPackages_17 = prev.gccNGPackages_17.overrideScope (_: gp: {
        gcc-unwrapped = gp.gcc-unwrapped.override {
          enableBackends = [ "aarch64-unknown-linux-musl" "alpha-linux-gnu" "arc-elf32" "arm-eabi" "avr-elf" "bfin-elf" "bpf-unknown-none" "c6x-elf" "cris-elf" "csky-elf" "epiphany-elf" "fr30-elf" "frv-elf" "ft32-elf" "amdgcn-amdhsa" "h8300-elf" "x86_64-pc-linux-gnu" "ia64-elf" "iq2000-elf" "lm32-elf" "m32r-elf" "m68k-elf" "mcore-elf" "microblaze-elf" "mips64-elf" "mmix-knuth-mmixware" "mn10300-elf" "moxie-elf" "msp430-elf" "nds32be-elf" "nvptx-none" "or1k-elf" "hppa64-linux-gnu" "pdp11-aout" "pru-elf" "riscv64-unknown-linux-gnu" "rl78-elf" "powerpc64-linux-gnu" "rx-elf" "s390x-linux-gnu" "sh-elf" "sparc64-linux" "v850e1-elf" "vax-linux-gnu" "visium-elf" "xstormy16-elf" "xtensa-elf"  ];
        };
      });
    })
  ];
}
