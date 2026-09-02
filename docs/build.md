# 构建系统详解

## 流水线总览

四个脚本按顺序组成完整流水线（CI 和本地都是同一套）：

```
build_kernel.sh   交叉编译内核：Image.gz + 机型 dtb + 内核 modules
build_rootfs.sh   下载 ubuntu-base tarball（sha256 校验）+ 创建固定 UUID 的空 ext4 镜像
assemble.sh       挂载镜像 + qemu-aarch64 chroot：装包、建用户、locale、串口 console、
                  装内核 modules、套用机型定制（overlay / 预置二进制 / post-assemble 钩子）
pack.sh           mkbootimg 出 boot.img、img2simg 出 sparse rootfs.img、下载 lk2nd、
                  生成 flash.sh/flash.bat 和 BUILD-INFO.txt，打 zip
```

所有脚本接受同一个参数：机型配置文件，如 `./scripts/build_kernel.sh devices/wt88047.env`。

## 配置分层

```
config/base.env            # 全局：ubuntu-base 源、预装包清单、时区、locale
devices/wt88047.env        # 机型：内核 submodule/dtb、mkbootimg 布局参数、rootfs UUID、
                           #       cmdline、lk2nd 版本+sha256、主机名、默认用户、串口、webssh 源
devices/wt88047/           # 机型定制目录（全部可选，见下）
```

### 机型定制目录 `devices/<codename>/`

| 文件/目录 | 何时被使用 | 作用 |
| --- | --- | --- |
| `kernel.config` | build_kernel.sh | 内核配置片段，defconfig 之后用内核自带的 `scripts/kconfig/merge_config.sh` 合并，再 `olddefconfig` |
| `rootfs/` | assemble.sh | overlay，原样拷入根文件系统。systemd unit 放 `rootfs/etc/systemd/system/`，脚本放 `rootfs/usr/local/lib/umeko/` |
| `post-assemble.sh` | assemble.sh | 根文件系统组装完成后在 chroot 里执行的钩子：`systemctl enable …`、编译安装额外软件等。环境变量带 `DEVICE_CODENAME` `DEVICE_NAME` `SOC` `DEFAULT_USER` |

wt88047 的内核片段（`devices/wt88047/kernel.config`）在 msm8916_defconfig 基础上打开了：内置 g_serial（ttyGS0 USB 串口控制台）、CAN + gs_usb（USB CAN 适配器）、RNDIS host、FRAMEBUFFER_CONSOLE（屏幕控制台）。这些参考自 KlipperPhonesLinux 广受好评的红米2 刷机包所用的内核配置。

## CI 流水线（.github/workflows/build.yml）

- **触发**：push 到 `main` 或手动触发 → 构建并上传 artifact（保留 14 天）；push `v*` tag → 构建并发布 GitHub Release
- **环境**：`ubuntu-24.04` runner，依赖安装清单与 [Dockerfile](docker.md) 一致
- **缓存**：
  - ccache（key `kernel-wt88047`）——第二次起内核编译从 ~8 分钟降到 1~2 分钟
  - ubuntu-base tarball（`.cache/` 目录）
- **并发控制**：同一 ref 的重复 push 会取消正在进行的旧构建

## 可复现性设计

- 内核 submodule 钉死在固定 commit（`git submodule` 天然带 SHA）
- lk2nd / ubuntu-base / webssh 二进制全部带 sha256 校验
- rootfs ext4 使用固定 UUID（`93afcbbe-…`），cmdline 里 `root=UUID=` 因此可复现
- 每次构建生成 `BUILD-INFO.txt` 记录所有来源和版本

## 添加新机型

1. 复制 `devices/wt88047.env` 为 `devices/<codename>.env`，改 dtb、mkbootimg 参数、cmdline、rootfs UUID 等
2. 如需不同 SoC 的内核，`git submodule add` 到 `kernels/`
3. 按需创建 `devices/<codename>/`（kernel.config / rootfs overlay / post-assemble.sh）
4. 在 `.github/workflows/build.yml` 把 `DEVICE_ENV` 改成 matrix 以并行构建多机型

## 已知边界

- 内核版本号在本地 Windows 工作区直接构建时可能带 `-dirty` 后缀（Windows 文件系统丢 exec 位/符号链接导致内核 git 树变"脏"）。用[容器内构建](docker.md)则无此问题；CI 上始终干净
- Ubuntu 24.04 的 `mkbootimg` 包漏装了 `gki` python 模块（上游打包 bug，只在用 GKI 签名参数时才真正需要它）。`pack.sh` 检测到会自动在宿主机装一个 stub 模块，无需人工干预
