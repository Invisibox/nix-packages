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

Nautilus 输出是 `nautilus-env` 组合环境。使用它时，将
`NAUTILUS_4_EXTENSION_DIR` 设置为 `${package}/lib/nautilus/extensions-4`；终端选择等 dconf 设置由消费端配置。
Neiro 不包含厂商调音 XML、用户状态或服务定义。

## 构建与检查

```sh
nix flake show
nix build '.#brave-origin-beta'
nix build '.#gamescope-patched'
nix build '.#nautilus-with-extensions'
nix fmt -- --check .
./scripts/test-update-neiro.sh
nix flake check --print-build-logs
```

`nix flake check` 会构建全部六个包，Neiro 保留上游测试。首次使用 Git flake 前，需将文件加入 Git：

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

也导出 `overlays.default`，供需要使用自己的 nixpkgs 或覆盖依赖的配置使用。overlay 新增上述六个名字，保留 nixpkgs 原有的 `gamescope` 和 `nautilus`；使用不同依赖时，需要重新构建。

本地修改包定义后，在 `nix-config` 中执行 `nix flake update nix-packages`，刷新本地 input 的锁定快照。

## 更新版本

```sh
./scripts/update-all.sh
# 或仅更新一个应用：
./scripts/update-neiro.sh
# Gamescope、Nautilus 以及构建依赖随 nixpkgs 更新：
nix flake update nixpkgs
nix flake check --print-build-logs
```

四个应用的更新脚本位于 `scripts/`，GitHub API 请求支持 `GITHUB_TOKEN`。
Brave Origin 跟踪含指定 beta deb 的发布，Paseo 和 OxideTerm 跟踪最新 Release；Neiro 跟踪默认分支提交，并在源码、Cargo 哈希和构建测试通过后替换包定义。
Gamescope 的补丁可能在后续 nixpkgs 中失效或已被上游合并，届时需调整补丁后再更新。

## GitHub Actions 与 Cachix

`.github/workflows/packages.yml` 在 push、PR 和手动运行时检查、构建六个包；PR job 只有只读仓库权限。每天 UTC 03:17（北京时间 11:17）更新 nixpkgs 和四个应用。
定时更新只有在检查和全部构建通过后才提交，失败不会推送版本更新。手动运行可勾选 `update` 执行相同更新过程。
使用标准 `ubuntu-latest` runner，公开仓库适用 GitHub Actions 免费额度。

发布后，在 GitHub 仓库的 **Settings → Secrets and variables → Actions** 设置：

| 类型 | 名称 | 内容 |
| --- | --- | --- |
| Variable | `CACHIX_CACHE_NAME` | 你的 Cachix 缓存名 |
| Secret | `CACHIX_AUTH_TOKEN` | 对该缓存有写入权限的 token |

未设置缓存名时，CI 仍正常构建。启用写入时，需同时设置缓存名和 token；PR 只读取公开缓存。
工作流只上传六个顶层包的输出，依赖继续由现有 substituter 提供，以控制 5 GB 免费存储占用。
同时允许仓库 Actions 写入内容，以便定时任务提交已验证的版本更新。若主分支启用了禁止直接推送的保护规则，需允许该工作流更新，或改为手动合并更新。

消费端还需要配置 Cachix 提供的 substituter URL 和 public key，例如使用 `cachix use <cache-name>`，或在 NixOS 的 `nix.settings` 中声明它们。
本仓库不保存 token，也不预设缓存名、公钥或 GitHub remote。
