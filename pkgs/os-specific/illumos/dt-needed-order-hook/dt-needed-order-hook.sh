# Fail the build if any shipped ELF object lists `libc.so.1` in DT_NEEDED
# *ahead of* `libgcc_s.so.1`.
#
# illumos `libc.so.1` exports the C++ unwind ABI itself (`_Unwind_RaiseException`,
# `_Unwind_Resume`, `_Unwind_GetIP`, ... -- the Solaris unwinder in
# `lib/libc/port/unwind`). `ld.so.1` resolves breadth-first, so whichever of the
# two comes first in DT_NEEDED wins for the whole process. If that is libc,
# libstdc++'s `__cxa_throw` binds to libc's unwinder, which does not do gcc's
# PT_GNU_EH_FRAME/dl_iterate_phdr FDE lookup -- it finds a handler for nothing
# and *every* C++ throw calls std::terminate:
#
#     terminate called after throwing an instance of 'nix::BadURL'
#     terminate called recursively
#
# The missing `what():` line is the tell: __verbose_terminate_handler re-entering.
# That is not hypothetical; it crash-looped svc:/site/nix-daemon:default until
# libdl.so.1 stopped being a symlink to libc.so.1.
#
# Only objects naming BOTH libraries can suffer this. A C program with
# libc.so.1 first is perfectly fine.

illumosDtNeededOrderCheck() {
    local readelf="@readelf@"

    if [ ! -x "$readelf" ]; then
        echo "illumos DT_NEEDED order check: CANNOT RUN -- no readelf at $readelf" >&2
        echo "  This check is not optional. Fix the hook rather than skipping it." >&2
        return 1
    fi

    local bad=0 n=0
    local f needed libcPos gccPos i

    while IFS= read -r -d '' f; do
        [ -f "$f" ] || continue
        [ -L "$f" ] && continue

        needed=$("$readelf" -d "$f" 2>/dev/null | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p') || continue
        [ -n "$needed" ] || continue

        libcPos=-1
        gccPos=-1
        i=0
        local lib
        while IFS= read -r lib; do
            case "$lib" in
                libc.so.1)      [ "$libcPos" -lt 0 ] && libcPos=$i ;;
                libgcc_s.so.1)  [ "$gccPos"  -lt 0 ] && gccPos=$i ;;
            esac
            i=$((i + 1))
        done <<< "$needed"

        [ "$libcPos" -ge 0 ] && [ "$gccPos" -ge 0 ] || continue
        n=$((n + 1))
        if [ "$libcPos" -lt "$gccPos" ]; then
            bad=$((bad + 1))
            echo "illumos DT_NEEDED order check: FAIL $f" >&2
            echo "    libc.so.1 is at DT_NEEDED slot $libcPos, libgcc_s.so.1 at slot $gccPos." >&2
            echo "    ld.so.1 will bind __cxa_throw to libc's unwinder and every C++ throw" >&2
            echo "    in this process will call std::terminate. DT_NEEDED was:" >&2
            printf '      %s\n' $needed >&2
        fi
    done < <(find "$prefix" -type f -print0)

    if [ "$bad" -gt 0 ]; then
        echo "illumos DT_NEEDED order check: $bad of $n C++-unwinding object(s) put libc.so.1 first." >&2
        echo "  Usually a stray -lc/-ldl early on the link line, or a .pc file's Libs:." >&2
        return 1
    fi

    echo "illumos DT_NEEDED order check: $n object(s) name both libc.so.1 and libgcc_s.so.1, ordering OK"
}

fixupOutputHooks+=(illumosDtNeededOrderCheck)
