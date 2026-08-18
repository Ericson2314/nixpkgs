#!/usr/bin/env bash
#
# Regenerate pkgs/os-specific/illumos/patches/ from an illumos-gate checkout.
#
# illumos-gate is the source of truth for these patches: each one is a commit on
# a branch there, and this script only exports them. To change a patch, change
# the commit and re-run this.
#
# Note that `filterPatches` (see pkgs/build-support/filter-patches) strips each
# patch's preamble before hashing, so commit ids and rebases do not affect
# anything Nix builds -- only the hunks themselves do. That is why
# `--zero-commit` is safe and why rebasing the branch is free.
#
# Usage: update-patches.sh <illumos-gate-checkout> [base] [branch]

set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

gate=${1:?usage: update-patches.sh <illumos-gate-checkout> [base] [branch]}
base=${2:-origin/master}
branch=${3:-virtiofs}

rm -f "$here/patches"/*.patch

git -C "$gate" format-patch \
  --no-signature \
  --zero-commit \
  --no-numbered \
  -o "$here/patches" \
  "$base..$branch"

echo
echo "Regenerated $(ls -1 "$here/patches"/*.patch | wc -l) patches from $branch."
echo "Remember to re-pin pkgs/source.nix to the matching $base revision:"
git -C "$gate" rev-parse "$base"
