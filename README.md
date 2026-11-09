# nix-packages

个人软件包 flake，仅导出 `x86_64-linux`。包定义从 `nix-config` 迁出，服务、桌面偏好及设备资源继续由系统配置管理。

| 输出 | 初始版本 | 定制内容 |
| --- | --- | --- |
| `brave-origin-beta` | `1.99.48` | 官方 deb 重新打包，ELF 修正、启动包装、桌面入口 |
| `paseo-desktop` | `0.13.1` | 官方 deb 重新打包、动态链接修正、XDG 协议处理 |
| `oxideterm` | `2.2.6` | 官方 deb 重新打包，CLI / GUI、WebKit 运行环境 |
| `neiro` | `0.2.0` / `2c48e7e` | Rust 源码构建，PipeWire / WirePlumber / ffmpeg 包装 |
| `gamescope-patched` | 跟随 nixpkgs | `-fno-fast-math` 和 Gamescope 退出修复补丁 |
| `nautilus-with-extensions` | 跟随 nixpkgs | GStreamer good/bad，以及 nautilus-python、open-any-terminal、code-nautilus、Flickernaut、GVfs、Sushi |
| `wechat-jailed` | 跟随 nixpkgs `wechat` | 原生 Wayland、jail.nix 沙箱、独立数据目录、Documents 只读、网页门户 |
| `qq-jailed` | 跟随 nixpkgs `qq` | 同上 |
| `baidunetdisk-jailed` | `8.7.0` | 官方 deb + FHS 运行环境，使用相同沙箱 |
| `baidupcs-rust` | `2.4.0` | BaiduPCS-Rust 官方 Linux x86_64 发布包，直接运行本机 Web 服务 |

Nautilus 输出是 `nautilus-env` 组合环境。使用它时，将
`NAUTILUS_4_EXTENSION_DIR` 设置为 `${package}/lib/nautilus/extensions-4`；终端选择等 dconf 设置由消费端配置。
Neiro 不包含厂商调音 XML、用户状态或服务定义。

`packages/` 中每个软件目录以 `package.nix` 为入口，由 nixpkgs 的 `packagesFromDirectoryRecursive` 自动发现，同时导出到 `packages.x86_64-linux` 和 `overlays.default`。新增包只需新增目录；共享沙箱和更新器工具放在 `lib/`。

## 构建与检查

```sh
nix flake show
nix build '.#brave-origin-beta'
nix build '.#gamescope-patched'
nix build '.#nautilus-with-extensions'
nix build '.#wechat-jailed' '.#qq-jailed' '.#baidunetdisk-jailed'
nix build '.#baidupcs-rust'
nix fmt -- --check .
./scripts/test-update-neiro.sh
./scripts/test-update-all.sh
./scripts/test-select-builds.sh
nix flake check --print-build-logs
nix run '.#checks.x86_64-linux.jailed-desktop-policy'
```

`nix flake check` 会构建全部十个包和沙箱检查工具，Neiro 保留上游测试。沙箱检查需在构建沙箱外运行上面的 `nix run`，会启动临时的 headless Weston 和测试 D-Bus，不访问真实应用数据或打开浏览器。首次使用 Git flake 前，需将文件加入 Git：

```sh
git add .
```

## 在系统配置中使用

本地开发期间：

```nix
inputs.nix-packages.url = "path:/home/zh/Documents/nix-packages";
```

发布后改为 `github:<owner>/<repo>`，并执行 `nix flake update nix-packages`。
不要给这个 input 添加 `inputs.nixpkgs.follows`；直接消费已锁定的包输出，才能与本仓库 CI 使用相同的依赖和构建哈希：

```nix
{inputs, pkgs, ...}: {
  environment.systemPackages = [
    inputs.nix-packages.packages.${pkgs.stdenv.hostPlatform.system}.brave-origin-beta
  ];
}
```

也导出 `overlays.default`，供需要使用自己的 nixpkgs 或覆盖依赖的配置使用。overlay 新增上述十个名字，保留 nixpkgs 原有软件包；消费端需允许微信、QQ 和官方百度网盘客户端的 unfree 许可，使用不同依赖时需要重新构建。
官方百度网盘客户端仍依赖 GTK2，flake 将其弃用标记降为警告；使用 overlay 安装时需设置 `nixpkgs.config.problems.handlers."gtk+".broken = "warn"`。Paseo 使用官方 deb，不再携带 AppImage 中的 GTK2 兼容库。

运行 `baidupcs-rust` 后，在 `http://127.0.0.1:18888` 打开 Web 界面；配置、登录数据和默认下载目录保存在 `$XDG_DATA_HOME/baidupcs-rust`（默认 `~/.local/share/baidupcs-rust`）。它不使用 jail.nix 沙箱，与 `baidunetdisk-jailed` 可同时安装和使用。

本地修改包定义后，在 `nix-config` 中执行 `nix flake update nix-packages`，刷新本地 input 的锁定快照。

## 微信、QQ、百度网盘沙箱

三个包通过 [~alexdavid/jail.nix](https://git.sr.ht/~alexdavid/jail.nix) 包装，适用于 Wayland 会话：

- `~/Documents` 只读，沙箱内的 `Documents/jail` 为空且只读，避免各应用读取彼此的私有数据；其余宿主用户目录不挂载，包括 Downloads、SSH 密钥和浏览器配置。应用内也不能通过文件选择门户读取其他位置。
- 每个应用的可写 HOME 独立保存在 `~/Documents/jail/<包名>/`，首次启动时自动创建，登录状态、缓存、接收文件和网盘下载保存在这里。应用通过自己的 HOME 读写这些数据；共享 Documents 不能作为下载目标。旧的 `~/.local/share/jail.nix/home/<包名>/` 不自动迁移或删除。
- 允许网络、GPU、PulseAudio / PipeWire 音频播放和麦克风录音、`/dev/video*` 摄像头设备、Wayland 及剪贴板；旧 X11 客户端使用沙箱内部独立的 xwayland-satellite。
- 微信使用 nixpkgs 的 deb 打包和原生 Wayland 输入支持，由上游启动脚本选择 Wayland 和 text-input-v3；沙箱不设置微信的旧式输入法变量和 `QT_QPA_PLATFORM`。
- QQ 和百度网盘按 Flathub 的包级配置，仅转发宿主已设置的 `QT_IM_MODULE`、`GTK_IM_MODULE` 和 `XMODIFIERS`，不强制指定输入法。QQ 使用 nixpkgs 已提供的 Wayland IME 和 text-input-v3 参数；百度网盘通过沙箱内的 Xwayland 运行。
- D-Bus 允许通知、托盘、Fcitx5，以及桌面门户的 `OpenURI`、`Settings.Read/ReadOne/ReadAll` 和 `SettingChanged`。应用可读取系统深浅色模式并接收切换通知；应用内需选择跟随系统。微信另允许注册 `org.kde.*`，适配其 Qt 旧式托盘服务名，与 Flathub 微信的权限一致。`xdg-open` 和 `$BROWSER` 只接受 HTTP(S)，通过宿主门户使用系统默认浏览器；禁止调用 `OpenFile`、文件选择器及任意宿主服务。
- 安装后的命令 `wechat-jailed`、`qq-jailed`、`baidunetdisk-jailed`，以及兼容命令 `wechat`、`qq`、`baidunetdisk` 和桌面入口均经过沙箱。

网络、音频和剪贴板属于主动授予的权限；这三个客户端仍可上传 Documents 中的内容。旧 Flatpak 的安装和用户数据不会自动删除或迁移。
百度网盘的 deb URL 和 SHA-256 固定在 `packages/baidunetdisk-jailed/unwrapped.nix`，升级时一并更新并重新构建；微信和 QQ 随 `nix flake update nixpkgs` 更新。

## 更新版本

```sh
# 更新全部 flake inputs（nixpkgs、jail-nix）：
nix flake update
# 更新独立打包的四个应用：
./scripts/update-all.sh
# 或仅更新一个应用：
nix run '.#neiro.updateScript'
nix flake check --print-build-logs
```

四个应用通过 `passthru.updateScript` 导出更新器，可在仓库内执行 `nix run '.#<包名>.updateScript'`；运行环境由 Nix 提供，工作目录自动切到 Git 仓库根目录。`update-all.sh` 自动发现这些更新器，逐个执行并汇总失败。原有 `scripts/update-*.sh` 仍可直接调用，GitHub API 请求支持 `GITHUB_TOKEN`。
Paseo 和 OxideTerm 使用仓库锁定的 nixpkgs 提供的 `nix-update`，通过 GitHub Release API 跟踪最新稳定版并更新源码哈希，无需额外安装工具。
Brave Origin 保留按指定 beta deb 筛选发布的脚本；Neiro 跟踪默认分支提交，并在源码、Cargo 哈希和构建测试通过后替换包定义。
Gamescope、Nautilus、微信和 QQ 随 nixpkgs 更新，百度网盘暂时手动维护版本和哈希。
Gamescope 的补丁可能在后续 nixpkgs 中失效或已被上游合并，届时需调整补丁后再更新。

## GitHub Actions 与 Attic

参考[自动化 NUR](https://blog.starryreverie.cc/posts/2026/automate-nur/)，`.github/workflows/packages.yml` 分为求值、构建和提交更新三个阶段，仅运行于 `x86_64-linux` 的 `ubuntu-latest` runner。长期公开缓存使用 [Attic](https://cache.455500.xyz/)，缓存名为 `nix-packages`。

构建阶段继续启用 [Magic Nix Cache](https://github.com/DeterminateSystems/magic-nix-cache-action)，无需额外密钥。接入 Attic 后，求值阶段仅查询公开缓存，避免包仅命中 CI 内部缓存就跳过发布；构建阶段仍可从 Magic Nix Cache 下载后上传到 Attic。尚未配置 Attic 时，保持原求值缓存行为。

求值阶段检查格式、脚本回归和 flake，并通过锁定 nixpkgs 提供的 `nix-eval-jobs --check-cache-status` 并行求值。`scripts/select-builds.sh` 为公开缓存缺失的每个包生成一个 matrix job；已由更新脚本在本地构建的包也进入构建阶段，以便上传。缓存被清理或上次构建失败后，即使 Git 内容没有变化也会重试；全部命中时跳过构建。每个 job 独立完成，单包失败不取消其他包。目前 matrix 串行运行，每次上传也限制为一路，适配 1.5 GB 内存 VPS。

沙箱检查工具仍按 derivation 变化运行权限测试：push 对比推送前的提交，PR 对比与目标分支的共同祖先，定时更新对比更新前的 HEAD，手动不更新时对比上一个提交。缺少基线或基线无法求值时运行权限测试。测试验证 Documents 只读、其他用户目录不可见、私有数据持久化、网页打开、桌面通知、摄像头设备挂载、音频 socket 连接、主题读取与切换通知、托盘注册及回调，以及 D-Bus 文件选择器隔离；使用模拟设备、临时 headless Wayland 和 D-Bus，Ubuntu runner 为 bubblewrap 开放用户命名空间。

每天 UTC 03:17（北京时间 11:17）更新 nixpkgs、jail-nix 和四个自定义应用；手动运行可勾选 `update`。求值阶段将更新后的源码打包，构建和提交阶段使用同一份快照。所有检查和构建通过后，由独立 job 提交版本更新；仅此 job 拥有仓库写权限。公开仓库适用 GitHub Actions 免费额度。

发布后，在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 设置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Secret | `ATTIC_TOKEN` | Dokploy attic 容器内 `/var/lib/atticd/credentials/github-actions.token` 的完整内容 |
| Variable | `ATTIC_PUBLIC_KEY` | `https://cache.455500.xyz/nix-packages/attic-cache-info` 中的完整 `public_key` |

先保存 Secret，再保存 Variable。`ATTIC_PUBLIC_KEY` 非空即切换到 Attic；API 地址 `https://cache.455500.xyz/` 和缓存名已固定在工作流中。只有默认分支上的成功包上传，PR 只读且不接收写令牌。启用后缺少 token 或上传失败会使对应 job 失败。

首次迁移先保留原 `CACHIX_CACHE_NAME` / `CACHIX_AUTH_TOKEN`，在 **Actions → Packages → Run workflow** 选择默认分支，勾选 `cache_backfill`、不勾选 `update`。它会包含当前全部包的所有 output，读取旧 Cachix 以复用已有结果，再以 `attic push --stdin --jobs 1` 上传到 Attic；官方签名依赖由 Attic 默认过滤，沙箱测试工具不上传。缺失的包在 runner 上构建，无需在 VPS 上搬运 Nix store。该操作覆盖当前版本，需要保留的历史版本需另行迁移。

普通运行启用 Attic 后不再读取或写入 Cachix；尚未设置 `ATTIC_PUBLIC_KEY` 时沿用原 Cachix 流程。回填、实际下载及备份恢复验证完成后可删除旧 Cachix 变量与 Secret。完整部署和轮换步骤见 [Dokploy-services/attic](https://github.com/Invisibox/Dokploy-services/tree/main/attic)。服务器默认生成的 CI token 有效期为 365 天；到期前递增 Dokploy 的 `ATTIC_CI_TOKEN_REVISION`、重新部署并更新 GitHub Secret。

同时允许仓库 Actions 写入内容，以便定时任务提交已验证的版本更新。若主分支启用了禁止直接推送的保护规则，需允许该工作流更新，或改为手动合并更新。

NixOS 消费端保留官方缓存，并添加：

```nix
nix.settings = {
  extra-substituters = [ "https://cache.455500.xyz/nix-packages" ];
  extra-trusted-public-keys = [ "nix-packages:替换为实际公钥" ];
};
```

公钥可用 `curl -fsS https://cache.455500.xyz/nix-packages/attic-cache-info | jq -r .public_key` 取得。普通消费端不需要 token；仓库不保存私钥或令牌。`cachix/install-nix-action` 仅负责安装 Nix，与选择哪个二进制缓存无关。
