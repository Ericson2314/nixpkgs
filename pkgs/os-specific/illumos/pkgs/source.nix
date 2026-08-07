{ fetchFromGitHub }:

# This must stay in step with the base revision the patches in ../patches were
# generated against; see ../update-patches.sh.
fetchFromGitHub {
  owner = "illumos";
  repo = "illumos-gate";
  rev = "f87c0a68ef64fc0c0effda47ee88951e83bb693c";
  hash = "sha256-sEa0GV1FyrgRFh80+9cSzzKNsTSPb5mmMB1ebecMJr0=";
}
