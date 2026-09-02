# 原理：手机为什么能跑主线 Linux

写给没有嵌入式背景的玩家。看完这一篇，你就明白这个仓库的每一步在干什么。

## 手机本来就是 Linux

Android 手机本身就跑 Linux 内核——只不过是**厂商魔改的旧版本**（比如红米2 原厂是 3.10 系列，高通加了几万行私有改动）。我们要做的事，是把这颗 SoC（MSM8916 / 骁龙410）换成**主线 Linux**（kernel.org 官方内核），再配上一个普通的 Linux 用户空间（Ubuntu）。

为什么偏偏 MSM8916 可以？因为 [msm8916-mainline](https://github.com/msm8916-mainline) 社区花了多年时间，把这颗 SoC 的时钟、电源管理、eMMC、显示、WiFi、触摸屏等驱动逐一贡献进了主线内核。今天主线内核里有现成的 `msm8916_defconfig` 和全套设备树（dtb），红米2 这样的机型开箱就能点亮。

## 启动链：从上电到 Ubuntu

按下电源键后，依次经过这些环节（加粗的是我们构建产物覆盖的部分）：

```
PBL(固化在芯片里) → SBL/aboot(原厂 bootloader) → lk2nd(boot 分区)
    → 主线内核 Image.gz + dtb(也打包在 boot 分区) → Ubuntu rootfs(userdata 分区)
```

- **PBL / SBL**：高通的固化引导程序，不可更换，最终会把 boot 分区的内容加载起来。
- **lk2nd**：刷在 boot 分区的"二级 bootloader"。它很小（400 多 KB），作用巨大：
  - 自动识别手机型号，从一堆 dtb 里选出匹配红米2 的那个；
  - 提供一个新的 fastboot 界面（原厂 fastboot 太老，刷不了大镜像），后续的 bootfs.img / rootfs.img 都是通过 lk2nd 的 fastboot 刷入的；
  - 扫描文件系统里的 `/extlinux/extlinux.conf`，按配置把内核接力启动起来。
  
  它**不替换原厂 bootloader**，所以刷坏了也容易救（用原厂 fastboot 重新刷 lk2nd 即可）。

- **主线内核**：就是 kernel.org 的 Linux（我们用 msm8916-mainline 维护的 v6.12 分支），编译出 `Image.gz`。它和 initramfs、各机型 dtb 一起作为普通文件放在 ext2 启动分区（bootfs.img）里，由 lk2nd 按 extlinux.conf 加载——换内核、改 cmdline 进系统改文件就行，不用重新打包刷机。
- **rootfs**：Ubuntu 24.04 arm64 的完整根文件系统（`/bin` `/etc` `/usr`……），做成 ext4 镜像刷进 userdata 分区（就是平时存照片的那个分区）。内核启动后按 UUID 找到它并挂载为 `/`，然后就是一台普通的 Ubuntu 机器了——`apt`、`systemd`、SSH 全都照常工作。

## dtb 是什么

设备树（Device Tree Blob）是一段描述"这台机器有什么硬件、接在哪个地址上"的数据。同一颗 MSM8916，红米2、红米3、各种平板的外设接法不同，就靠各自的 dtb 区分。内核是同一份，dtb 各选各的——这也是为什么 lk2nd "按机型选 dtb" 很重要。

## 那手机的基带、摄像头呢？

主线内核 + 主线驱动的覆盖范围有限：

- **好用**：CPU、eMMC/SD、屏幕（simplefb/DRM）、WiFi（wcn36xx + 从 modem 分区提取的固件）、USB、触摸屏、UART
- **半残/不可用**：打电话发短信的基带（modem 有驱动但没有拨号生态）、摄像头、硬件视频编解码

所以这个项目的定位是**把旧手机当低功耗 ARM Linux 上位机/小服务器用**（3D 打印机 Klipper 上位机是最初的动机），而不是当手机用。一台红米2 有 4 核 A53 + 1G 内存 + eMMC，自带屏幕电池 UPS，功耗两三瓦——做上位机刚刚好。

## 这个仓库在这条链里负责什么

| 环节 | 来源 |
| --- | --- |
| lk2nd | 官方 release 直接下载（sha256 校验） |
| 主线内核 | 从 msm8916-mainline/linux 源码交叉编译（可叠加机型配置片段） |
| Ubuntu rootfs | ubuntu-base 官方 tarball + chroot 装包 + 机型定制服务 |
| 打包 | mke2fs 出 ext2 的 bootfs.img（extlinux.conf + 内核 + initramfs + dtb），img2simg 出 sparse rootfs.img，生成刷机脚本（mkbootimg 打 boot.img 为 legacy 路线） |

全部由 GitHub Actions 自动完成，见[构建系统详解](build.md)。
