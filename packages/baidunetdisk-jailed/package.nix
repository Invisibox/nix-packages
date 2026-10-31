{
  callPackage,
  jail,
}:
callPackage ../../lib/jailed-desktop/package.nix {
  inherit jail;
  package = callPackage ./unwrapped.nix {};
  pname = "baidunetdisk-jailed";
  program = "baidunetdisk";
  fhs = true;
}
