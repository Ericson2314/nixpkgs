{ buildPackages }:

# illumos' link-editor as the gate makefiles want to call it: `$(LD)`.
#
# There is no logic here any more. Everything this used to do -- clearing
# SGS_SUPPORT, splitting `-Wl,a,b`, forcing POSIXLY_CORRECT -- now lives in
# ./illumos-ld.sh, the `ld` of ./bintools.nix, because the compiler driver
# reaches the same link-editor through the ordinary cc-wrapper ->
# bintools-wrapper chain and the two must not be able to drift apart. This file
# is the name the gate uses for it.
#
# It names `buildPackages.illumos.bintools` explicitly because splicing rewrites
# `nativeBuildInputs` but not string interpolation: a bare `${bintools}` here
# would refer to an illumos-hosted link-editor, which is not runnable on the
# build machine.
#
# Why `$(LD)` is still set at all, now that the link-editor is the stdenv's:
# cc-wrapper puts `x86_64-unknown-solaris2.11-ld` on PATH, not `ld`, and the
# gate's own default for the macro is the absolute path /usr/bin/ld. So the
# makefiles still have to be told where it is. What has gone away is the second,
# divergent copy of the link-editor's adjustments.
"${buildPackages.illumos.bintools}/bin/ld"
