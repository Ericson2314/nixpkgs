{
  # TODO: fix up and send to upstream
  "gcc/fix-collect2-paths.diff" = [
    {
      after = "15";
      path = ../15;
    }
  ];

  # In Git: https://github.com/Ericson2314/gcc/tree/regular-dirs-in-libgcc-15
  "libgcc/force-regular-dirs.patch" = [
    {
      after = "15";
      path = ../15;
    }
  ];
  # In Git: https://github.com/Ericson2314/gcc/tree/regular-dirs-in-libssp-15
  "libssp/force-regular-dirs.patch" = [
    {
      after = "15";
      path = ../15;
    }
  ];
  # In Git: https://github.com/Ericson2314/gcc/tree/libstdcxx-force-regular-dirs-15
  "libstdcxx/force-regular-dirs.patch" = [
    {
      after = "15";
      path = ../15;
    }
  ];
  # In Git: https://github.com/Ericson2314/gcc/tree/libgfortran-force-regular-dirs-15
  "libgfortran/force-regular-dirs.patch" = [
    {
      after = "15";
      path = ../15;
    }
  ];

  # THIS ENTRY WAS MISSING, AND FIVE COMPONENTS DID NOT EVALUATE BECAUSE OF IT.
  #
  # `getVersionFile` falls back to `metadata.versionDir`, which for a
  # `gitRelease` is `<ng>/git` -- a directory that does not exist. So
  # `libatomic`, and everything that reaches it (`libstdcxx`, `libgomp`,
  # `libgfortran`, `libsanitizer`), failed with
  #
  #   error: path '.../ng/git/libatomic/gthr-include.patch' does not exist
  #
  # at *evaluation* time, which is why no build log ever mentioned it. Note the
  # shape: the fallback is silent and points somewhere plausible, so a file that
  # is simply not listed here reads as a path typo rather than as a missing
  # table entry.
  "libatomic/gthr-include.patch" = [
    {
      after = "15";
      path = ../15;
    }
  ];
}
