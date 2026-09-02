# 机型列表

本仓库按机型目录（`devices/<codename>/`）索引所有支持的设备。每台机器一页，
记录硬件参数、支持状态、刷机要点和已知边界。

| 机型 | codename | SoC | 打包方式 | 状态 |
| --- | --- | --- | --- | --- |
| [红米 2 (Redmi 2)](wt88047.md) | `wt88047` | MSM8916 | mkbootimg（默认）+ extlinux 合并包 | CI 出包，真机在用 |
| [vivo Y23L](vivo-y23l.md) | `vivo-y23l` | MSM8916 | extlinux 合并包（需 lk1st 引导） | 实验性，待真机验证 |

## 状态标记说明

- **CI 出包**：每次代码变更自动构建，artifact / release 可直接下载
- **真机在用**：有真实设备刷入并日常使用验证
- **实验性**：构建链路已验证，但真机启动流程（尤其是引导器）尚未完全打通

## 想加新机型？

见[构建系统详解 — 添加新机型](../build.md)。同 SoC 的机型可以直接加入
extlinux 合并包（`DEVICE_ENVS_EXTLINUX`），共享同一份内核和 rootfs。
