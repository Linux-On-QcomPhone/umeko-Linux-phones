# 本地 Docker 构建

不依赖 GitHub Actions，在自己电脑上构建刷机包。Linux、macOS、Windows（Docker Desktop）均可。

## 为什么用 Docker

- 构建环境完全一致（Ubuntu 24.04 + 固定依赖清单），避免"我机器上能编"问题
- `assemble.sh` 需要 `mount` + `chroot`，容器必须加 `--privileged`，Docker 把这类特权操作圈在容器里，不碰宿主机
- 交叉编译 arm64 内核、qemu 模拟 arm64 chroot，在 x86_64 机器上即可全程完成

## 一键构建

```bash
git clone --recursive https://github.com/umeiko/umeko-Linux-phones.git
cd umeko-Linux-phones
./scripts/docker_build.sh devices/wt88047.env
```

Windows 用户在 **Git Bash** 里运行同样的命令。产物在 `./out/` 下。

脚本做了五件事：

1. 用 `docker/Dockerfile` 构建镜像 `umeko-build-env`（已存在则跳过）
2. 起一个特权容器 `umeko-build`（已存在则复用，保留 ccache 和下载缓存，二次构建会快很多）
3. 把工作区同步到容器**本地 ext4** 的 `/work`——不要小看这一步：在 Docker Desktop 的 bind mount（9p/virtiofs）上直接编译内核会慢几十倍
4. 在容器里跑完整四步流水线
5. 把 `out/` 拷回宿主机

常用环境变量：

```bash
PACK_VERSION=v1.0 ./scripts/docker_build.sh devices/wt88047.env   # 自定义产物版本号
docker rm -f umeko-build                                          # 清掉缓存容器从头来
```

## Dockerfile 里装了什么（和 CI 一致）

| 包 | 用途 |
| --- | --- |
| `gcc-aarch64-linux-gnu` | arm64 交叉编译器（编内核） |
| `build-essential bc bison flex libssl-dev libncurses-dev dwarves` | 内核构建的宿主机侧依赖 |
| `kmod` | `depmod`，生成 modules.dep |
| `ccache` | 编译缓存 |
| `qemu-user-static` | x86_64 上 chroot 进 arm64 rootfs 跑 apt/systemctl |
| `mkbootimg` | 打 Android boot.img |
| `android-sdk-libsparse-utils` | `img2simg`，转 fastboot 用的 sparse 镜像 |
| `e2fsprogs` | `mkfs.ext4` 等 |
| `zip curl ca-certificates git sudo python3` | 打包、下载校验、submodule、脚本运行环境 |

## 构建时要拉取的所有外部资源

| 资源 | 来源 | 校验 |
| --- | --- | --- |
| 主仓库 + `kernels/msm8916` submodule | GitHub（msm8916-mainline/linux，钉在固定 commit） | git SHA |
| ubuntu-base 24.04.3 arm64 tarball | cdimage.ubuntu.com | 官方 SHA256SUMS |
| lk2nd 23.1 | GitHub msm8916-mainline/lk2nd releases | 钉死的 sha256 |
| webssh arm64 二进制 | gitee umeko-env-init，钉在固定 commit | 钉死的 sha256 |
| apt 软件包 | archive.ubuntu.com（chroot 内） | apt 签名校验 |

!!! note "网络说明"
    GitHub 直连困难的环境，给容器配代理即可：在 `docker run` 或 `docker exec` 时加
    `-e https_proxy=http://host.docker.internal:<端口>`（Docker Desktop 上宿主机代理
    用 `host.docker.internal` 访问）。ubuntu/gitee 一般可直连。

## 手动分步调试

想单步调试某一步，进容器慢慢玩：

```bash
docker exec -it umeko-build bash
cd /work
./scripts/build_kernel.sh devices/wt88047.env   # 只编内核
./scripts/assemble.sh devices/wt88047.env       # 只重组 rootfs（需要内核 modules 已就位）
```

中间产物：

| 路径 | 内容 |
| --- | --- |
| `/work/build/kernel/` | 内核 O= 构建目录（`.config`、`Image.gz`、dtb） |
| `/work/build/modinst/` | 内核 modules 安装暂存区 |
| `/work/build/rootfs.img` | 组装完成的 ext4 根文件系统镜像（可 `mount -o loop` 进去检查） |
| `/work/build/pack/` | 打包暂存区（boot.img、sparse rootfs.img、flash 脚本） |
| `/work/.cache/` | 下载缓存（ubuntu-base tarball、webssh） |

## 不用 Docker 的原生构建

如果你本来就是 Linux（或 WSL2 Ubuntu 24.04），也可以不套容器，直接装依赖跑脚本：

```bash
sudo apt install gcc-aarch64-linux-gnu build-essential bc bison flex libssl-dev \
    libncurses-dev kmod ccache dwarves qemu-user-static mkbootimg \
    android-sdk-libsparse-utils e2fsprogs zip curl ca-certificates git sudo
git submodule update --init --depth 1
./scripts/build_kernel.sh  devices/wt88047.env
./scripts/build_rootfs.sh  devices/wt88047.env
./scripts/assemble.sh      devices/wt88047.env   # 需要 sudo（mount/chroot）
./scripts/pack.sh          devices/wt88047.env
```
