# We need to mangle names for hygiene, but also take parameters/overrides
# from the environment.
for var in "${var_templates_list[@]}"; do
    mangleVarList "$var" ${role_infixes[@]+"${role_infixes[@]}"}
done
for var in "${var_templates_bool[@]}"; do
    mangleVarBool "$var" ${role_infixes[@]+"${role_infixes[@]}"}
done

# `-B@out@/bin' forces cc to use ld-wrapper.sh when calling ld.
NIX_@platformPrefix@CFLAGS_COMPILE="-B@out@/bin/ $NIX_@platformPrefix@CFLAGS_COMPILE"

# Export and assign separately in order that a failing $(..) will fail
# the script.

if [ -e @out@/nix-support/libc-cflags ]; then
    NIX_@platformPrefix@CFLAGS_COMPILE="$(< @out@/nix-support/libc-cflags) $NIX_@platformPrefix@CFLAGS_COMPILE"
fi

if [ -e @out@/nix-support/cc-cflags ]; then
    NIX_@platformPrefix@CFLAGS_COMPILE="$(< @out@/nix-support/cc-cflags) $NIX_@platformPrefix@CFLAGS_COMPILE"
fi

if [ -e @out@/nix-support/cc-ldflags ]; then
    NIX_@platformPrefix@LDFLAGS+=" $(< @out@/nix-support/cc-ldflags)"
fi

# That way forked processes will not extend these environment variables again.
export NIX_CC_WRAPPER_@platformPrefix@FLAGS_SET=1
