# umeko-Linux-phones

把旧手机变成 Linux 上位机 —— 自动构建系统。
（Successor of [KlipperPhonesLinux](https://github.com/umeiko/KlipperPhonesLinux)：从"收集刷机包"转向"全自动构建刷机包"。）

**当前状态**：一期试点 —— 红米2 (wt88047 / msm8916) + Ubuntu 24.04 base 最小系统（不含 Klipper）。全部由 GitHub Actions 构建。

## 构建产物

每个构建产出一个 zip 刷机包：

| 文件 | 说明 |
| --- | --- |
| `lk2nd-msm8916.img` | 二级 bootloader（[msm8916-mainline/lk2nd](https://github.com/msm8916-mainline/lk2nd) 官方 release，sha256 校验） |
| `boot.img` | 主线内核 `Image.gz` + appended dtb（无 initramfs，`root=UUID=` 直挂根分区） |
| `rootfs.img` | Ubuntu 24.04 arm64 最小系统（sparse ext4，刷入 userdata） |
| `flash.sh` / `flash.bat` | fastboot 一键刷入脚本 |
| `BUILD-INFO.txt` | 构建溯源信息 |

## 构建流程（GitHub Actions）

```
build_kernel.sh    交叉编译 msm8916-mainline/linux @ v6.12.1-msm8916（msm8916_defconfig + ccache）
build_rootfs.sh    下载 ubuntu-base 24.04 arm64 tarball（SHA256SUMS 校验），创建固定 UUID 的 ext4 镜像
assemble.sh        mount + qemu-aarch64 chroot：装包/用户/locale/串口 console，装入内核 modules
pack.sh            mkbootimg 出 boot.img，img2simg 出 rootfs.img，下载 lk2nd，生成刷机脚本，打 zip
```

- push 到 `main` 或手动触发 → 构建并上传 artifact
- push `v*` tag → 构建并发布 GitHub Release

## 添加新机型

1. 复制 `devices/wt88047.env` 为 `devices/<codename>.env`，改 dtb、mkbootimg 参数、cmdline 等
2. 如需不同 SoC 内核，添加对应 submodule 到 `kernels/`
3. 在 `.github/workflows/build.yml` 中把 `DEVICE_ENV` 改成 matrix

## 仓库结构

```
├── .github/workflows/build.yml   # CI 流水线
├── config/base.env               # 全局配置（ubuntu-base 源、预装包、时区）
├── devices/wt88047.env           # 机型配置（内核/dtb/mkbootimg 参数/lk2nd/cmdline）
├── kernels/msm8916               # submodule：msm8916-mainline/linux @ v6.12.1-msm8916
└── scripts/                      # build_kernel / build_rootfs / assemble / pack
```

## 本地构建（可选）

脚本可在 WSL2 (Ubuntu 24.04) 上直接运行，依赖同 CI：

```bash
sudo apt install gcc-aarch64-linux-gnu bc bison flex libssl-dev libncurses-dev kmod ccache \
    qemu-user-static mkbootimg android-sdk-libsparse-utils e2fsprogs zip curl
git submodule update --init --depth 1
./scripts/build_kernel.sh  devices/wt88047.env
./scripts/build_rootfs.sh  devices/wt88047.env
./scripts/assemble.sh      devices/wt88047.env   # 需要 sudo（mount/chroot）
./scripts/pack.sh          devices/wt88047.env
```

## 刷机（简述）

1. 手机进入 stock fastboot，运行包内 `flash.sh`（或 Windows 下 `flash.bat`）
2. 脚本先刷 lk2nd，重启按住音量减进入 lk2nd 的 fastboot，再刷 boot.img 和 rootfs.img
3. 首次启动较慢；登录 `umeko` / `1234`
4. 控制台入口：屏幕、UART（ttyMSM0）、USB 串口 gadget（ttyGS0，插上电脑即出串口）、SSH（先用 nmtui 配 WiFi）

## 已知限制 / TODO

- 根分区不会自动扩满 userdata：手动 `sudo resize2fs /dev/mmcblk0p<N>`（分区号以实际为准）
- 暂无 USB 网络（rndis/ecm）配置，联网需先经串口/USB串口用 `nmtui` 配 WiFi
- 二期：Klipper 全家桶（klipper/moonraker/fluidd/KlipperScreen）chroot 安装、更多机型 matrix、自动扩容
