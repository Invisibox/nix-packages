{
  callPackage,
  jail,
  wechat,
}:
callPackage ../../lib/jailed-desktop/package.nix {
  inherit jail;
  package = wechat;
  pname = "wechat-jailed";
  program = "wechat";
  fhs = true;
}
