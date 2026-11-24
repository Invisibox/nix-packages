{sable-desktop}:
sable-desktop.overrideAttrs (finalAttrs: {
  pname = "sable-next";
  meta =
    sable-desktop.meta
    // {
      changelog = "https://git.sable.moe/SableClient/sable-next/releases/tag/v${finalAttrs.version}";
    };
})
