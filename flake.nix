{
  description = "Personal Nix packages for x86_64-linux";

  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";

  outputs = {
    self,
    nixpkgs,
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [self.overlays.default];
    };
    packageNames = [
      "brave-origin-beta"
      "paseo-desktop"
      "oxideterm"
      "neiro"
      "gamescope-patched"
      "nautilus-with-extensions"
    ];
  in {
    overlays.default = import ./overlay.nix;
    packages.${system} = nixpkgs.lib.genAttrs packageNames (name: pkgs.${name});
    checks.${system} = self.packages.${system};
    formatter.${system} = pkgs.alejandra;
  };
}
