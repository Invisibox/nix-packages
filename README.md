# nix-packages

个人软件包 flake，仅导出 `x86_64-linux`。包定义从 `nix-config` 迁出，服务、桌面偏好及设备资源继续由系统配置管理。

| 输出 | 初始版本 | 定制内容 |
| --- | --- | --- |
| `brave-origin-beta` | `1.99.48` | 官方 deb 重新打包，ELF 修正、启动包装、桌面入口 |
| `paseo-desktop` | `0.13.1` | 官方 AppImage 提取、动态链接修正、XDG 协议处理 |
| `oxideterm` | `2.2.6` | 官方 deb 重新打包，CLI / GUI、WebKit 运行环境 |
| `neiro` | `0.2.0` / `2c48e7e` | Rust 源码构建，PipeWire / WirePlumber / ffmpeg 包装 |
| `gamescope-patched` | 跟随 nixpkgs | `-fno-fast-math` 和 Gamescope 退出修复补丁 |
| `nautilus-with-extensions` | 跟随 nixpkgs | GStreamer good/bad，以及 nautilus-python、open-any-terminal、code-nautilus、Flickernaut、GVfs、Sushi |
| `wechat-jailed` | `4.1.13.26` | nixpkgs PR #560225、原生 Wayland、jail.nix 沙箱、独立数据目录、Documents 只读、网页门户 |
| `qq-jailed` | 跟随 nixpkgs `qq` | 同上 |
| `baidunetdisk-jailed` | `8.7.0` | 官方 deb + FHS 运行环境，使用相同沙箱 |

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
nix fmt -- --check .
./scripts/test-update-neiro.sh
./scripts/test-update-all.sh
./scripts/test-select-builds.sh
nix flake check --print-build-logs
nix run '.#checks.x86_64-linux.jailed-desktop-policy'
```

`nix flake check` 会构建全部九个包和沙箱检查工具，Neiro 保留上游测试。沙箱检查需在构建沙箱外运行上面的 `nix run`，会启动临时的 headless Weston 和测试 D-Bus，不访问真实应用数据或打开浏览器。首次使用 Git flake 前，需将文件加入 Git：

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

也导出 `overlays.default`，供需要使用自己的 nixpkgs 或覆盖依赖的配置使用。overlay 新增上述九个名字，保留 nixpkgs 原有软件包；消费端需允许微信、QQ 和百度网盘的 unfree 许可，使用不同依赖时需要重新构建。

本地修改包定义后，在 `nix-config` 中执行 `nix flake update nix-packages`，刷新本地 input 的锁定快照。

## 微信、QQ、百度网盘沙箱

三个包通过 [~alexdavid/jail.nix](https://git.sr.ht/~alexdavid/jail.nix) 包装，适用于 Wayland 会话：

- `~/Documents` 只读；其余宿主用户目录不挂载，包括 Downloads、SSH 密钥和浏览器配置。应用内也不能通过文件选择门户读取其他位置。
- 每个应用的可写 HOME 独立保存在 `~/.local/share/jail.nix/home/<包名>/`，登录状态、缓存、接收文件和网盘下载保存在这里。Documents 不能作为下载目标，可选择应用私有 HOME 下的目录。
- 允许网络、GPU、PulseAudio / PipeWire 音频播放和麦克风录音、`/dev/video*` 摄像头设备、Wayland 及剪贴板；旧 X11 客户端使用沙箱内部独立的 xwayland-satellite。
- 微信采用 [nixpkgs PR #560225](https://github.com/NixOS/nixpkgs/pull/560225) 的 deb 打包和原生 Wayland 输入支持，由上游启动脚本选择 Wayland 和 text-input-v3；沙箱不再设置微信的旧式输入法变量和 `QT_QPA_PLATFORM`。
- QQ 和百度网盘按 Flathub 的包级配置，仅转发宿主已设置的 `QT_IM_MODULE`、`GTK_IM_MODULE` 和 `XMODIFIERS`，不强制指定输入法。QQ 使用 nixpkgs 已提供的 Wayland IME 和 text-input-v3 参数；百度网盘通过沙箱内的 Xwayland 运行。
- D-Bus 允许通知、托盘、Fcitx5，以及桌面门户的 `OpenURI`、`Settings.Read/ReadOne/ReadAll` 和 `SettingChanged`。应用可读取系统深浅色模式并接收切换通知；应用内需选择跟随系统。微信另允许注册 `org.kde.*`，适配其 Qt 旧式托盘服务名，与 Flathub 微信的权限一致。`xdg-open` 和 `$BROWSER` 只接受 HTTP(S)，通过宿主门户使用系统默认浏览器；禁止调用 `OpenFile`、文件选择器及任意宿主服务。
- 安装后的命令 `wechat-jailed`、`qq-jailed`、`baidunetdisk-jailed`，以及兼容命令 `wechat`、`qq`、`baidunetdisk` 和桌面入口均经过沙箱。

网络、音频和剪贴板属于主动授予的权限；这三个客户端仍可上传 Documents 中的内容。旧 Flatpak 的安装和用户数据不会自动删除或迁移。
百度网盘的 deb URL 和 SHA-256 固定在 `packages/baidunetdisk-jailed/unwrapped.nix`，升级时一并更新并重新构建；QQ 随 `nix flake update nixpkgs` 更新。微信暂固定上述 PR 的提交，待 nixpkgs 合并后移除临时导入，恢复跟随 nixpkgs。

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
Gamescope、Nautilus 和 QQ 随 nixpkgs 更新；微信暂固定 PR #560225，百度网盘暂时手动维护版本和哈希。
Gamescope 的补丁可能在后续 nixpkgs 中失效或已被上游合并，届时需调整补丁后再更新。

## GitHub Actions 与 Cachix

参考[自动化 NUR](https://blog.starryreverie.cc/posts/2026/automate-nur/)，`.github/workflows/packages.yml` 分为求值、并行构建和提交更新三个阶段，仅运行于 `x86_64-linux` 的 `ubuntu-latest` runner。

求值和构建阶段均启用 [Magic Nix Cache](https://github.com/DeterminateSystems/magic-nix-cache-action)，通过 GitHub Actions 缓存复用 Nix 构建结果，无需额外密钥。该缓存仅供 CI 使用；消费端仍通过下述 Cachix 配置获取构建结果。

求值阶段检查格式、脚本回归和 flake，并通过锁定 nixpkgs 提供的 `nix-eval-jobs --check-cache-status` 并行求值。配置 Cachix 后先读取该缓存，`scripts/select-builds.sh` 为远端缓存缺失的每个包生成一个 matrix job；已由更新脚本在本地构建的包也会进入构建阶段，以便上传。缓存被清理或上次构建失败后，即使 Git 内容没有变化也会重试；全部命中缓存时跳过构建。每个 job 独立完成，单包失败不取消其他包。

沙箱检查工具仍按 derivation 变化运行权限测试：push 对比推送前的提交，PR 对比与目标分支的共同祖先，定时更新对比更新前的 HEAD，手动不更新时对比上一个提交。缺少基线或基线无法求值时运行权限测试。测试验证 Documents 只读、其他用户目录不可见、私有数据持久化、网页打开、桌面通知、摄像头设备挂载、音频 socket 连接、主题读取与切换通知、托盘注册及回调，以及 D-Bus 文件选择器隔离；使用模拟设备、临时 headless Wayland 和 D-Bus，Ubuntu runner 为 bubblewrap 开放用户命名空间。

每天 UTC 03:17（北京时间 11:17）更新 nixpkgs、jail-nix 和四个自定义应用；手动运行可勾选 `update`。求值阶段将更新后的源码打包，构建和提交阶段使用同一份快照。所有检查和构建通过后，由独立 job 提交版本更新；仅此 job 拥有仓库写权限。公开仓库适用 GitHub Actions 免费额度。

发布后，在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 设置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `CACHIX_CACHE_NAME` | 你的 Cachix 缓存名 |
| Secret | `CACHIX_AUTH_TOKEN` | 对该缓存有写入权限的 token |

未设置缓存名时，CI 仍正常构建。启用写入时，需同时设置缓存名和 token；只有默认分支上的成功构建会上传，PR 只读取公开缓存。
工作流关闭 Cachix 自动推送，仅对成功包的所有 output 显式调用 `cachix push`，上传其运行时闭包，以控制 5 GiB 免费存储占用；沙箱测试工具不上传。
同时允许仓库 Actions 写入内容，以便定时任务提交已验证的版本更新。若主分支启用了禁止直接推送的保护规则，需允许该工作流更新，或改为手动合并更新。

消费端还需要配置 Cachix 提供的 substituter URL 和 public key，例如使用 `cachix use <cache-name>`，或在 NixOS 的 `nix.settings` 中声明它们。
本仓库不保存 token，也不预设缓存名、公钥或 GitHub remote。
