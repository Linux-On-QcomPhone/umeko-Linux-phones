# 可选路线：extlinux 启动（实验性）

!!! warning "实验性功能"
    本页描述的是一条**研究中的备选启动路线**，不是默认方案。
    默认刷机包仍走 mkbootimg 的 Android boot.img 路线（见[构建系统详解](build.md)）。

## 这是什么

默认方案里，内核和 dtb 被 `mkbootimg` 打成一个 Android `boot.img`，刷到 boot 分区
lk2nd 之后的 512KiB 偏移处。lk2nd 实际上还支持另一种更通用的启动方式：
**直接扫描文件系统里的 `/extlinux/extlinux.conf`**（和 U-Boot、depthcharge 同款格式），
按配置加载内核、dtb 和可选的 initramfs。

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
- `initrd` 可省略（我们现在就不用 initramfs）
- `fdtdir` 模式下按设备数据库依次尝试 `<dir>/qcom/<name>.dtb`、`<dir>/qcom-<name>.dtb`、
  `<dir>/<name>.dtb`；也可以用 `fdt` 写死路径
- **启动内存上限 50MiB**（内核解压后 + initramfs + dtb 共享，msm8916 无单独配置）
- **重要限制**：lk2nd 的 ext2 驱动只支持经典的直接/间接块映射，**不支持 extents**，
  所以启动文件系统必须是纯 ext2，ext4 不行（我们的 userdata rootfs 是 ext4，
  放不了 extlinux.conf）

## 与 mkbootimg 路线对比

| | mkbootimg（现状） | extlinux（实验） |
| --- | --- | --- |
| 内核/dtb 存放 | 打死在 boot.img 二进制里 | 文件系统里的普通文件 |
| 改 cmdline/换内核 | 重新打包刷 boot 分区 | 进系统改文件/换文件即可 |
| 多系统/多内核 | 不支持 | 天然支持（多个 label、多份内核） |
| initramfs | 我们没有，加要改打包 | 加一行 `initrd` 即可 |
| 依赖 | mkbootimg（Ubuntu 24.04 包还是坏的，要打补丁） | 只需 mke2fs（e2fsprogs） |
| 成熟度 | 已验证、CI 全绿 | 待真机验证 |

## 我们的打包方案

`scripts/pack_extlinux.sh`（与 `pack.sh` 同接口）：

```bash
PACK_VERSION=test scripts/pack_extlinux.sh devices/wt88047.env
```

产物布局（红米2 wt88047，system 分区在默认方案中闲置，正好利用）：

```
boot     <- lk2nd-msm8916.img   （原厂 fastboot，刷一次）
system   <- bootfs.img          （64MB 纯 ext2，mke2fs -t ext2 -d 生成）
userdata <- rootfs.img          （sparse ext4，与默认方案相同）
```

`bootfs.img` 内容：

```
/extlinux/extlinux.conf     # default umeko; linux /Image.gz; fdt /dtbs/qcom/...; append <cmdline>
/Image.gz                   # 内核（gzip，lk2nd 自动解压）
/dtbs/qcom/msm8916-wingtech-wt88047.dtb
```

已在构建容器内验证：镜像可正常挂载、无 extents 特性、内容与配置正确。
**尚未在真机上验证启动。**

## 和 UEFI 路线的关系

extlinux 是"半标准化"：配置格式标准，但引导器仍是 lk2nd。
完整的 UEFI 路线（lk2nd → gen-uboot-img 的 U-Boot → systemd-boot/UKI）更通用，
U-Boot 的 `syslinux`/`sysboot` 命令本身也吃 extlinux.conf——所以即使将来迁移 UEFI，
extlinux 这套文件布局也可以直接复用，不算弯路。

## 待办

- [ ] 真机刷入验证（刷 bootfs.img 到 system 分区）
- [ ] 验证通过后：给 `pack.sh`/`pack_extlinux.sh` 加统一的 `PACK_METHOD` 开关，CI 出双包
- [ ] 评估在 extlinux 之上加 initramfs（做真正的开机自动扩容、LUKS 等）
