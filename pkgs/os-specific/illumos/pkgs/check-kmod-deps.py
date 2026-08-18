#!/usr/bin/env python3
"""Fail the build when a staged kernel module needs a module we did not build.

Every loadable module declares its hard dependencies in its Makefile as
`LDFLAGS += -N <class>/<name>`, and krtld resolves each of those at modload()
time, before the module runs a line of its own code.  Nothing in the illumos
build checks that the named module exists, because on a real system the answer
is always yes -- the gate builds everything.  A hand-picked module list (see
`kmodNames` in unix.nix) removes that guarantee, and the failure mode is
uniquely nasty: the module simply does not load, and the symptom surfaces
several layers away.  `misc/ipc` missing meant shmsys/semsys/msgsys all built,
staged, and silently failed to load, with SysV IPC absent from the system.

So do the check here, against the assembled tree, where it is mechanical.

Mechanics worth knowing before you edit this:

  * Kernel modules are ET_REL.  `readelf -d` prints NOTHING for them, because
    it looks for a PT_DYNAMIC program header and a relocatable object has no
    program headers at all.  The `.dynamic` *section* is there regardless, and
    that is what we parse.

  * The strings are NOT in `.dynstr` -- these objects have no `.dynstr`.  The
    `.dynamic` section's sh_link points at the plain `.strtab`.  Follow
    sh_link; do not look the section up by name.

  * Module names are `<class>/<name>` (`misc/mac`, `fs/specfs`, `drv/vtfs`)
    and resolve to `<root>/kernel/<class>/amd64/<name>`, or the same under
    `platform/i86pc/kernel/` or `usr/kernel/`.

A DT_NEEDED with no `/` in it is not a module reference and is skipped.  Only
`unix` itself has any (`genunix` and `dtracestubs`): those are ordinary link
dependencies of the kernel proper, satisfied by `lib/libgenunix.so` and by the
DTrace stub object generated inside the `unix` build, not by anything
loadable.  That is the rule, rather than a list of names to ignore.
"""

import os
import struct
import sys

DT_NULL = 0
DT_NEEDED = 1


def dt_needed(path):
    """DT_NEEDED strings of an ELF64 little-endian object, or None if not one."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF" or data[4] != 2 or data[5] != 1:
        return None

    (e_shoff,) = struct.unpack_from("<Q", data, 0x28)
    e_shentsize, e_shnum, _ = struct.unpack_from("<HHH", data, 0x3A)
    if e_shoff == 0 or e_shnum == 0:
        return []

    sections = []
    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        sh_type, = struct.unpack_from("<I", data, off + 4)
        sh_offset, sh_size = struct.unpack_from("<QQ", data, off + 0x18)
        sh_link, = struct.unpack_from("<I", data, off + 0x28)
        sections.append((sh_type, sh_offset, sh_size, sh_link))

    SHT_DYNAMIC = 6
    needed = []
    for sh_type, sh_offset, sh_size, sh_link in sections:
        if sh_type != SHT_DYNAMIC:
            continue
        # sh_link is the string table for this .dynamic -- .strtab, not
        # .dynstr, in an ET_REL kernel module.
        _, str_off, str_size, _ = sections[sh_link]
        for off in range(sh_offset, sh_offset + sh_size, 16):
            tag, val = struct.unpack_from("<qQ", data, off)
            if tag == DT_NULL:
                break
            if tag == DT_NEEDED:
                blob = data[str_off + val : str_off + str_size]
                needed.append(blob.split(b"\0", 1)[0].decode())
    return needed


def module_name(rel):
    """`kernel/fs/amd64/specfs` -> `fs/specfs`; `kernel/amd64/genunix` -> `genunix`.

    Handles the three module roots krtld searches: `platform/<plat>/kernel`,
    `kernel` and `usr/kernel`.
    """
    parts = rel.split("/")
    if parts[0] == "platform":
        parts = parts[2:]
    if parts[0] == "usr":
        parts = parts[1:]
    if not parts or parts[0] != "kernel":
        return None
    parts = [p for p in parts[1:] if p != "amd64"]
    if len(parts) == 1:
        return parts[0]
    if len(parts) == 2:
        return "/".join(parts)
    return None


def main():
    root, nix_file = sys.argv[1], sys.argv[2]
    kmod_names = sys.argv[3:]

    # `misc/ipc` -> the kmodNames entry that would provide it, if we can tell.
    # kmodNames entries are `<uts-dir>/<name>`, e.g. `intel/ipc`, `i86pc/pcie`.
    known_dirs = sorted({n.split("/")[0] for n in kmod_names}) or ["intel"]

    provided = {}
    deps = {}
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                continue
            rel = os.path.relpath(path, root)
            try:
                needed = dt_needed(path)
            except (OSError, struct.error, UnicodeDecodeError):
                continue
            if needed is None:
                continue
            mod = module_name(rel)
            if mod is None:
                continue
            provided[mod] = rel
            if needed:
                deps[rel] = (mod, needed)

    failures = []
    checked = 0
    for rel in sorted(deps):
        mod, needed = deps[rel]
        for dep in needed:
            if "/" not in dep:
                # Not a krtld module reference; see the module docstring.
                continue
            checked += 1
            if dep not in provided:
                failures.append((mod, rel, dep))

    if failures:
        lines = [
            "",
            "*** unresolvable kernel module dependencies ***",
            "",
            "krtld resolves a module's -N dependencies at modload() time.  Each of",
            "the modules below declares a DT_NEEDED on a module that is not in the",
            "assembled tree, so it will build and stage and then silently fail to",
            "load, and you will see the consequence somewhere else entirely.",
            "",
        ]
        for mod, rel, dep in failures:
            suggestions = " or ".join('"%s/%s"' % (d, dep.split("/")[1]) for d in known_dirs)
            lines += [
                "  %s (%s) needs %s, which is not built." % (mod, rel, dep),
                "      fix: add %s to `kmodNames` in" % suggestions,
                "           %s" % nix_file,
                "           (whichever of those directories the module's source lives in)",
                "",
            ]
        lines += [
            "%d module dependencies checked, %d unresolved."
            % (checked, len(failures)),
            "",
        ]
        sys.stderr.write("\n".join(lines))
        return 1

    sys.stderr.write(
        "kernel module dependency check: %d modules, %d -N dependencies, all resolved\n"
        % (len(provided), checked)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
