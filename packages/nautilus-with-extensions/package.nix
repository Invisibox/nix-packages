{
  nautilus,
  buildEnv,
  gst_all_1,
  nautilus-python,
  nautilus-open-any-terminal,
  code-nautilus,
  gnomeExtensions,
  gvfs,
  sushi,
}: let
  nautilusWithGst = nautilus.overrideAttrs (prev: {
    buildInputs =
      (prev.buildInputs or [])
      ++ [
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
      ];
  });
in
  buildEnv {
    name = "nautilus-env";
    paths = [
      nautilusWithGst
      nautilus-python
      nautilus-open-any-terminal
      code-nautilus
      gnomeExtensions.flickernaut
      gvfs
      sushi
    ];
  }
  // {meta.mainProgram = nautilus.meta.mainProgram;}
