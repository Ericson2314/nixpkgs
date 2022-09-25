# See pkgs/build-support/setup-hooks/role.bash
getHostRole

export NIX_LDFLAGS${role_post}+=" -legacy"
export NIX_CFLAGS_COMPILE${role_post}+=" -I@out@/include0"
export NIX_CFLAGS_COMPILE${role_post}+=" -I@out@/include1"
