{ fetchFromGitHub }:

# This must stay in step with the base revision the patches in ../patches were
# generated against; see ../update-patches.sh.
fetchFromGitHub {
  owner = "illumos";
  repo = "illumos-gate";
  rev = "7d32109ee973334ac380edd5174e9ef912c7731d";
  hash = "sha256-+F8gE4NGAcH7KWUPFxAvtr+dFOanN2yl6EVcTAJN/c0=";
}
