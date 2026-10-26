{
  callPackage,
  jail,
  wechat,
}:
callPackage ../jailed-desktop/package.nix {
  inherit jail;
  package = wechat;
  pname = "wechat-jailed";
  program = "wechat";
  fhs = true;
}
