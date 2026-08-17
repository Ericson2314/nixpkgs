"""Remove DWARF from an illumos kernel object without disturbing its layout.

    strip-dwarf.py FILE...

Rewrites each FILE in place, dropping the contents of every .debug_* section
(and the .rela.debug_* that relocate them) and repacking what is left. Every
other section keeps its bytes exactly, every section keeps its *index*, and
nothing that a program header covers moves by a single byte.

Why not objcopy
---------------

GNU binutils is the only stripper available on the build machine -- illumos'
own strip(1) is mcs(1) from cmd/sgs, which is cross-built here and cannot run
on a Linux host, and tools/sgs (the NATIVE_BUILD bootstrap tree that gives us
`ld`) does not include mcs. But objcopy gets three separate things wrong on
these files, two of them silently:

 1. It rebuilds .strtab, and in doing so deletes the kmod dependency names.
    A module's `-N misc/md5`-style dependencies are DT_NEEDED entries in
    .dynamic whose d_val is a byte offset into .strtab, and the link editor
    parks those strings at the very tail of .strtab, past the last symbol name.
    They belong to no symbol, so BFD's strtab rebuild drops them. Measured on
    drv/ip: .strtab shrinks from 0x12bd5 to exactly 0x12b7a bytes, which is
    precisely the offset of the first DT_NEEDED string -- all eight of
    "misc/md5", "crypto/swrand", "misc/hook", "misc/neti", "misc/cc",
    "cc/cc_sunreno", "cc/cc_newreno" and "cc/cc_cubic" go, and the offsets that
    remain in .dynamic now point past the end of the section.

 2. It zeroes .dynamic's sh_link, which is how krtld finds that string table in
    the first place (uts/common/krtld/kobj.c:1835-1844 rejects the module with
    "sh_link not a string table for section %d").

 3. On `unix` it reorders allocatable sections into signed address order.
    unix's 1:1 mapped dboot segment lives at 0xc00000 and everything else at
    0xfffffffffb800000, so dboot -- which the link and mbh_patch both placed
    first, at file offset 0x158 -- ends up last. Measured: the LOAD moves to
    0x1ddb28 and the 0x1BADB002 multiboot magic is no longer anywhere in the
    first 40K, where MB1 (8K) and MB2 (32K) require it. The file looks correct
    and no loader will boot it.

Only (2) is repairable after the fact; (1) and (3) are not. Hence this.

How it works
------------

Two rules make the whole thing safe:

  o Nothing with SHF_ALLOC moves. Allocatable sections keep their exact file
    offsets, so every PT_LOAD keeps describing the same bytes and the ELF
    header and program header table are untouched apart from e_shoff. This is
    what makes it safe to run on `unix`, where objcopy is not.

  o No section is removed from the table, only emptied. Dropping an entry would
    renumber everything after it and mean rewriting sh_link, sh_info, and every
    symbol's st_shndx -- including the STT_SECTION symbols for the debug
    sections themselves, which have nowhere valid to point once their section
    is gone. Setting sh_size to 0 instead leaves every index in the file
    correct by construction, and an empty .debug_info is exactly as
    uninteresting to krtld as an absent one.

What is left over is the non-allocatable survivors -- .symtab, .strtab,
.SUNW_ctf, .dynamic, .comment, the real .rela sections, .shstrtab -- which get
repacked, in their original order, into the space after the last allocatable
byte.

Everything is then checked against the original bytes before the file is
replaced; see verify().
"""

import os
import struct
import sys

SHF_ALLOC = 0x2
SHT_NOBITS = 8

EHDR_SHOFF = 0x28
EHDR_PHOFF = 0x20

MULTIBOOT_MAGIC = struct.pack("<I", 0x1BADB002)
# MB1 requires the header in the first 8K, MB2 in the first 32K. Check the
# tighter of the two.
MULTIBOOT_SEARCH = 8192


def align_up(n, a):
    return n if a <= 1 else (n + a - 1) // a * a


def is_elf64_le(data):
    # ELFCLASS64 and ELFDATA2LSB. The amd64 kernel is all of this except
    # `dboot`, which is a 32-bit ELF because it runs in protected mode before
    # the switch to long mode -- and which carries no DWARF worth chasing.
    return data[:4] == b"\x7fELF" and data[4] == 2 and data[5] == 1


class Elf:
    def __init__(self, data):
        self.data = data
        if not is_elf64_le(data):
            raise ValueError("not a 64-bit little-endian ELF")

        self.e_phoff, self.e_shoff = struct.unpack_from("<QQ", data, EHDR_PHOFF)
        (
            self.e_phentsize,
            self.e_phnum,
            self.e_shentsize,
            self.e_shnum,
            self.e_shstrndx,
        ) = struct.unpack_from("<HHHHH", data, 0x36)

        self.shdrs = [
            list(struct.unpack_from("<IIQQQQIIQQ", data, self.e_shoff + i * self.e_shentsize))
            for i in range(self.e_shnum)
        ]
        self.phdrs = [
            struct.unpack_from("<IIQQQQQQ", data, self.e_phoff + i * self.e_phentsize)
            for i in range(self.e_phnum)
        ]

        shstr = self.shdrs[self.e_shstrndx][4]
        self.names = []
        for sh in self.shdrs:
            off = shstr + sh[0]
            self.names.append(data[off : data.index(b"\0", off)].decode())

    # Field indices into the unpacked Elf64_Shdr above.
    NAME, TYPE, FLAGS, ADDR, OFFSET, SIZE, LINK, INFO, ALIGN, ENTSIZE = range(10)

    def body(self, i):
        sh = self.shdrs[i]
        if sh[self.TYPE] == SHT_NOBITS:
            return b""
        return self.data[sh[self.OFFSET] : sh[self.OFFSET] + sh[self.SIZE]]


def is_dwarf(name):
    return name.startswith(".debug") or name.startswith(".rela.debug")


def strip(path):
    with open(path, "rb") as f:
        original = f.read()

    if not is_elf64_le(original):
        return False

    elf = Elf(original)

    drop = {i for i, n in enumerate(elf.names) if is_dwarf(n)}
    if not drop:
        return False

    if ".SUNW_ctf" not in elf.names:
        raise SystemExit(
            f"{path}: no .SUNW_ctf. illumos keeps its type graph there and "
            f"DTrace and mdb read it out of the loaded module at run time, so "
            f"a kernel object without it means the build lost CTF."
        )

    keep_offsets = {}  # section index -> file offset in the new file
    cursor = 0

    # Immovable: the ELF header, the program header table, anything a program
    # header describes, and every allocatable section.
    cursor = max(cursor, 64, elf.e_phoff + elf.e_phnum * elf.e_phentsize)
    for p in elf.phdrs:
        cursor = max(cursor, p[2] + p[5])  # p_offset + p_filesz
    for i, sh in enumerate(elf.shdrs):
        if i == 0 or sh[Elf.TYPE] == SHT_NOBITS:
            continue
        if sh[Elf.FLAGS] & SHF_ALLOC:
            if i in drop:
                raise SystemExit(f"{path}: {elf.names[i]} is allocatable; refusing")
            keep_offsets[i] = sh[Elf.OFFSET]
            cursor = max(cursor, sh[Elf.OFFSET] + sh[Elf.SIZE])

    # Everything else is repacked, in file order, after that point.
    movable = sorted(
        (
            i
            for i, sh in enumerate(elf.shdrs)
            if i and i not in keep_offsets and sh[Elf.TYPE] != SHT_NOBITS
        ),
        key=lambda i: elf.shdrs[i][Elf.OFFSET],
    )
    for i in movable:
        sh = elf.shdrs[i]
        if i in drop:
            # Emptied, not removed. The index stays valid for sh_link, sh_info
            # and st_shndx; only the bytes go.
            sh[Elf.SIZE] = 0
            keep_offsets[i] = cursor
            continue
        cursor = align_up(cursor, sh[Elf.ALIGN])
        keep_offsets[i] = cursor
        cursor += sh[Elf.SIZE]

    new_shoff = align_up(cursor, 8)
    total = new_shoff + elf.e_shnum * elf.e_shentsize

    out = bytearray(total)
    # Start from the original so that every immovable byte -- header, program
    # headers, allocatable sections and any padding between them -- is carried
    # over verbatim rather than reconstructed.
    head = min(len(original), total)
    out[:head] = original[:head]

    for i in movable:
        if i in drop:
            continue
        off = keep_offsets[i]
        out[off : off + elf.shdrs[i][Elf.SIZE]] = elf.body(i)

    for i, sh in enumerate(elf.shdrs):
        if i in keep_offsets:
            sh[Elf.OFFSET] = keep_offsets[i]
        struct.pack_into("<IIQQQQIIQQ", out, new_shoff + i * elf.e_shentsize, *sh)

    struct.pack_into("<Q", out, EHDR_SHOFF, new_shoff)

    # Re-parsed from the original bytes rather than reusing `elf`, whose
    # shdrs this function has been mutating in place.
    verify(path, original, bytes(out), drop)

    # Same-directory temp plus rename, so a failure never leaves a half-written
    # kernel object behind.
    tmp = path + ".stripping"
    with open(tmp, "wb") as f:
        f.write(out)
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.rename(tmp, path)
    return True


def verify(path, original, new, drop):
    def fail(msg):
        raise SystemExit(f"{path}: {msg}")

    old = Elf(original)
    fresh = Elf(new)

    if fresh.e_shnum != old.e_shnum:
        fail("section count changed")
    if fresh.names != old.names:
        fail("section names changed")

    # The ELF header apart from e_shoff, and the whole program header table.
    if new[:EHDR_SHOFF] != original[:EHDR_SHOFF]:
        fail("ELF header changed")
    if new[EHDR_SHOFF + 8 : 64] != original[EHDR_SHOFF + 8 : 64]:
        fail("ELF header changed after e_shoff")
    phsz = old.e_phnum * old.e_phentsize
    if new[old.e_phoff : old.e_phoff + phsz] != original[old.e_phoff : old.e_phoff + phsz]:
        fail("program header table changed")

    for n, p in enumerate(old.phdrs):
        lo, sz = p[2], p[5]
        if new[lo : lo + sz] != original[lo : lo + sz]:
            fail(f"contents of program header {n} moved or changed")

    for i, name in enumerate(old.names):
        if i == 0:
            continue
        if i in drop:
            if fresh.shdrs[i][Elf.SIZE] != 0:
                fail(f"{name} was meant to be emptied")
            continue
        if fresh.body(i) != old.body(i):
            fail(f"contents of {name} changed")
        for field, label in ((Elf.LINK, "sh_link"), (Elf.INFO, "sh_info"),
                             (Elf.FLAGS, "sh_flags"), (Elf.TYPE, "sh_type"),
                             (Elf.ADDR, "sh_addr")):
            if fresh.shdrs[i][field] != old.shdrs[i][field]:
                fail(f"{name}: {label} changed")
        if fresh.shdrs[i][Elf.FLAGS] & SHF_ALLOC:
            if fresh.shdrs[i][Elf.OFFSET] != old.shdrs[i][Elf.OFFSET]:
                fail(f"{name} is allocatable and moved")

    # And the thing all of this is really protecting: on a file that carries a
    # multiboot header, it has to still be where the loader looks for it.
    was = original.find(MULTIBOOT_MAGIC, 0, MULTIBOOT_SEARCH)
    if was != -1 and new.find(MULTIBOOT_MAGIC, 0, MULTIBOOT_SEARCH) != was:
        fail(f"multiboot header left offset {was} / the first {MULTIBOOT_SEARCH} bytes")


if __name__ == "__main__":
    for arg in sys.argv[1:]:
        strip(arg)
