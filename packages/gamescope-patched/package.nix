{
  gamescope,
  fetchpatch,
}:
gamescope.overrideAttrs (_final: prev: {
  # https://github.com/ValveSoftware/gamescope/issues/1622
  NIX_CFLAGS_COMPILE = (prev.NIX_CFLAGS_COMPILE or []) ++ ["-fno-fast-math"];
  patches =
    (prev.patches or [])
    ++ [
      # Fix Gamescope not closing: https://github.com/ValveSoftware/gamescope/pull/1908
      (fetchpatch {
        url = "https://github.com/ValveSoftware/gamescope/commit/fa900b0694ffc8b835b91ef47a96ed90ac94823b.patch?full_index=1";
        hash = "sha256-eIHhgonP6YtSqvZx2B98PT1Ej4/o0pdU+4ubdiBgBM4=";
      })
    ];
})
