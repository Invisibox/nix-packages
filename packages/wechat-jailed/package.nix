{
  callPackage,
  jail,
}: let
  # NixOS/nixpkgs#560225; remove once it reaches the locked nixpkgs input.
  source = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/ea41ebe3e788f3f374e04885f4f60aca20efefed.tar.gz";
    sha256 = "sha256-15pPf5twUp7RMsUXCxdOHuwb8GKdw5PxF6zKwfelkUI=";
  };
in
  callPackage ../../lib/jailed-desktop/package.nix {
    inherit jail;
    package = callPackage "${source}/pkgs/by-name/we/wechat/package.nix" {};
    pname = "wechat-jailed";
    program = "wechat";
  }
