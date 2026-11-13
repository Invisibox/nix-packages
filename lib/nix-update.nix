let
  flake = builtins.getFlake (toString ../.);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
in
  pkgs.nix-update.overrideAttrs (old: {
    # Nix 2.35 metadata no longer materializes the source tree nix-update reads.
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace nix_update/options.py \
          --replace-fail '["nix", "flake", "metadata", "--json"]' \
                         '["nix", "flake", "archive", "--json"]'
      '';
  })
