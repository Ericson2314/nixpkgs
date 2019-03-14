# See cc-wrapper for comments.
if [ -e @out@/nix-support/libc-ldflags ]; then
    NIX_@platformPrefix@LDFLAGS+=" $(< @out@/nix-support/libc-ldflags)"
fi

if [ -e @out@/nix-support/libc-ldflags-before ]; then
    NIX_@platformPrefix@LDFLAGS_BEFORE="$(< @out@/nix-support/libc-ldflags-before) $NIX_@platformPrefix@LDFLAGS_BEFORE"
fi

export NIX_BINTOOLS_WRAPPER_@platformPrefix@FLAGS_SET=1
