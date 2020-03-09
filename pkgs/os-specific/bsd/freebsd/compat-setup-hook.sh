# See pkgs/build-support/setup-hooks/role.bash
getHostRole

export NIX_LDFLAGS${role_post}+=" -L@libbsd_out@"
export NIX_CFLAGS_COMPILE${role_post}+=" -I@libbsd_dev@/include/bsd"
export NIX_CFLAGS_COMPILE${role_post}+=" -DLIBBSD_OVERLAY"
