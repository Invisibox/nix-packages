{
  pkgs,
  sable-desktop,
}:
sable-desktop.overrideAttrs (finalAttrs: {
  pname = "sable-next";
  passthru =
    (sable-desktop.passthru or {})
    // {
      updateScript = pkgs.callPackage ../../lib/update-script.nix {
        script = "update-sable-next.sh";
      };
    };
  meta =
    sable-desktop.meta
    // {
      changelog = "https://git.sable.moe/SableClient/sable-next/releases/tag/v${finalAttrs.version}";
    };
})
