# extlinux 启动（默认路线）

extlinux 是**默认且唯一由 CI 构建**的打包路线（mkbootimg 转为
legacy，见下文对比）。红米 2 与 vivo Y23L 均已真机验证启动。

## 这是什么

早期方案里，内核和 dtb 被 `mkbootimg` 打成一个 Android `boot.img`，刷到 boot 分区
lk2nd 之后的 512KiB 偏移处。lk2nd 实际上还支持另一种更通用的启动方式：
**直接扫描文件系统里的 `/extlinux/extlinux.conf`**（和 U-Boot、depthcharge 同款格式），
按配置加载内核、dtb 和 initramfs。

pmOS 的 msm8916 通用设备包就有这条路线的官方实现
（`device-qcom-msm8916-kernel-extlinux`，"Use lk2nd to boot via extlinux.conf"）。

## lk2nd 的 extlinux 支持细节

来源：[lk2nd Documentation/boot.md](https://github.com/msm8916-mainline/lk2nd/blob/main/Documentation/boot.md)
与源码 `lk2nd/boot/extlinux.c`（23.1 已包含，我们用的就是这个版本）：

- 扫描**所有 ≥16MiB 的分区**（外加 boot 分区 +512KiB 偏移处），尝试以 ext2 挂载，
  找 `/extlinux/extlinux.conf`
- 支持的指令：`label` / `default` / `linux`(=`kernel`) / `initrd` / `fdt` / `fdtdir` /
  `append` / `fdtoverlays`；总是启动 `default` 标签
- 内核可以是 gzip 压缩的（自动解压，我们的 `Image.gz` 直接用）
- `initrd` 可省略，但我们默认带 initramfs（`root=UUID=` 必须由 initramfs
  里的 blkid/udev 解析，内核自己认不了 UUID）
- `fdtdir` 模式下按设备数据库依次尝试 `<dir>/qcom/<name>.dtb`、`<dir>/qcom-<name>.dtb`、
  `<dir>/<name>.dtb`；也可以用 `fdt` 写死路径
- **启动内存上限 50MiB**（内核解压后 + initramfs + dtb 共享，msm8916 无单独配置）
- **重要限制**：lk2nd 的 ext2 驱动只支持经典的直接/间接块映射，**不支持 extents**，
  所以启动文件系统必须是纯 ext2，ext4 不行（我们的 userdata rootfs 是 ext4，
  放不了 extlinux.conf）

## 与 mkbootimg 路线对比

| | mkbootimg（legacy） | extlinux（默认） |
| --- | --- | --- |
| 内核/dtb 存放 | 打死在 boot.img 二进制里 | 文件系统里的普通文件 |
| 改 cmdline/换内核 | 重新打包刷 boot 分区 | 进系统改文件/换文件即可 |
| 多系统/多内核 | 不支持 | 天然支持（多个 label、多份内核） |
| initramfs | 加要改打包 | 加一行 `initrd` 即可（默认带） |
| 依赖 | mkbootimg（Ubuntu 24.04 包还是坏的，要打补丁） | 只需 mke2fs（e2fsprogs） |
| 成熟度 | 已验证，CI 不再自动构建 | 红米2 + vivo Y23L 真机验证通过 |

## 我们的打包方案

`scripts/pack_extlinux.sh`（与 `pack.sh` 同接口，支持多机型）：

```bash
# 单机型
PACK_VERSION=test scripts/pack_extlinux.sh devices/wt88047.env
# 合并包：一个包同时支持红米2 和 vivo Y23L
PACK_VERSION=test scripts/pack_extlinux.sh devices/wt88047.env devices/vivo-y23l.env
```

产物布局（红米2 wt88047，system 分区在默认方案中闲置，正好利用）：

```
boot     <- lk2nd-msm8916.img   （原厂 fastboot，刷一次）
system   <- bootfs.img          （64MB 纯 ext2，mke2fs -t ext2 -d 生成）
userdata <- rootfs.img          （sparse ext4，与默认方案相同）
```

多机型合并包的 `bootfs.img` 内容：

```
/extlinux/extlinux.conf     # default umeko; linux /Image.gz; fdtdir /dtbs; append <cmdline>
/Image.gz                   # 内核（gzip，lk2nd 自动解压）
/dtbs/qcom/msm8916-wingtech-wt88047.dtb    # 红米2
/dtbs/qcom/msm8916-vivo-pd1419.dtb         # vivo Y23L
```

`fdtdir /dtbs` 模式下，lk2nd/lk1st 根据自己的设备数据库识别机器型号，
再到 `/dtbs/qcom/` 里挑对应的 dtb——所以一个包能通吃多台机器。

构建容器内验证过镜像可正常挂载、无 extents 特性、内容与配置正确；
**红米 2 与 vivo Y23L 均已真机验证启动**（Y23L 截图见[机型页](devices/vivo-y23l.md)）。

## vivo Y23L（pd1419）的特殊情况

Y23L 属于 vivo CDP 家族（pd1304/pd1403/pd1410/pd1419），lk2nd 设备数据库里有，
dtb 文件名映射为 `msm8916-vivo-pd1419`。但这家族是 lk2nd 官方标注的
"quirky" 设备：**原厂系统是 Android 4.4.4，aboot 只有 32 位，加载不了 64 位的
lk2nd**，需要用 lk1st（一级引导，直接替换 aboot 分区）并同时替换 tz/hyp 固件。

- lk1st 需按面板编译：Y23L 有 nt35510s 和 orise8012a 两种屏幕，
  分别用 `LK2ND_DISPLAY=nt35510s_fwvga_cmd` / `orise8012a_fwvga_cmd` 构建
  （本仓库 CI 尚未集成 lk1st 构建；本地构建方式见 lk2nd 源码
  `lk2nd/device/dts/msm8916/msm8916-vivo-cdp-1.dts` 的注释）
- 内核侧两个面板驱动（`panel-vivo-nt35510s` / `panel-vivo-orise8012a`）
  由设备 patch 提供，已在合并包里编译为模块；lk1st/lk2nd 的 match-panel
  机制会把 dtb 里的面板 compatible 改写成实际探测到的那颗
- **tz/hyp 替换的具体来源和刷入流程尚未整理进本仓库**，刷机前请先确认
  这一步骤（参考 msm8916-mainline 社区）

合并包对 Y23L 的意义：OS 部分（内核 dtb、面板模块、rootfs）开箱即用，
只有引导器这一步与红米2不同。

## 和 UEFI 路线的关系

extlinux 是"半标准化"：配置格式标准，但引导器仍是 lk2nd。
完整的 UEFI 路线（lk2nd → gen-uboot-img 的 U-Boot → systemd-boot/UKI）更通用，
U-Boot 的 `syslinux`/`sysboot` 命令本身也吃 extlinux.conf——所以即使将来迁移 UEFI，
extlinux 这套文件布局也可以直接复用，不算弯路。

## 待办

- [x] 多机型合并包（fdtdir，红米2 + vivo Y23L），CI 出包
- [x] Y23L 引导流程调研：底包（gpt/hyp/rpm/sbl1/tz/recovery）+ lk1st 刷 aboot
      + bootfs 刷 boot，参考 KlipperPhonesLinux vivo 刷机包；lk1st 两种面板
      版本已验证可用 tag 23.1 源码编译
- [x] 真机刷入验证：红米2（lk2nd + bootfs.img 刷 system 分区）与
      vivo Y23L（lk1st + bootfs.img 刷 boot 分区）均已启动到登录界面
- [x] extlinux 之上默认带 initramfs（`mkinitramfs` + zstd 生成，bootfs 固定
      UUID 由机型 fstab 挂到 /boot；`root=UUID=` 依赖它解析）
- [ ] vivo Y23L：lk1st 构建接入 CI（main 分支有生成头文件冲突，需钉 23.1）
