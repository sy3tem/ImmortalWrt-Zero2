# ImmortalWrt-Zero2

NanoPi Zero2（RK3528A）的 ImmortalWrt 主线云编译仓库，GitHub Actions 驱动。

## 设备

- **NanoPi Zero2**：SoC RK3528A（四核 A53 + Mali-450），1GB/2GB LPDDR4/X
- **存储**：microSD + eMMC 模块座
- **网口**：单口千兆 = gmac1（RGMII → RTL8211F）
- **WiFi**：M.2 Key-E 2230（PCIe 2.1），需自插模块（RTL8822CE）
- **USB**：1× USB2.0 Type-A Host + 1× USB-C（Device / 线刷）
- **LED**：SYS（GPIO4 PB0，heartbeat）+ LED1（GPIO4 PB1）
- **按键**：RESET / RECOVERY / MASK（救砖进 Maskrom）
- **调试串口**：UART2，3.3V TTL，**1500000bps**

## 方案

- **源码**：ImmortalWrt 主线 `immortalwrt/immortalwrt` master（内核 6.18）
- **设备支持**：**上游原生**，无需自写设备树
  - `Device/friendlyarm_nanopi-zero2` → `target/linux/rockchip/image/armv8.mk`
  - `U-Boot/nanopi-zero2-rk3528` → `package/boot/uboot-rockchip/Makefile`
  - 内核 DTS → `patches-6.18` 的 `073-04`（USB）与 `110`（PCIe）补丁
- **本仓库只补**：`board.d` 网口 + LED 映射（`Scripts/Inject-ZERO2.sh`）
- **U-Boot**：主线 `nanopi-zero2-rk3528`，**在 Linux 启动前释放 RGMII PHY 复位**
  （这是千兆网能工作的前提；官方 wiki 的 u-boot 2017.09 反而是老路子）
- **代理**：**Open-Box**（[liandu2024/Open-Box](https://github.com/liandu2024/Open-Box)，sing-box 一体化方案）
  - **编译期预置**四个组件（app/runtime/kernel/geo，约 75MB），刷完即用、无需联网
  - 组件下载 + SHA256 校验见 `Scripts/Fetch-OpenBox.sh`
  - 首启自动建 `/opt` 分区并部署，见 `target-patch/zero2-opt-openbox.init`
  - 固件**不含** passwall / xray / iStore
- **无线**：**不编任何 WiFi 驱动**（Zero2 的 M.2 Key-E 不接模块）
- **形态**：**旁路由**（相关设置需自行配置，固件不预置）
- **附加**：argon 主题、dockerman、ttyd、turboacc 等（见 `Config/GENERAL.txt`）

> **为什么不用官方固件里的 loader？**
> 官方只提供 u-boot 2017.09。本方案全程使用上游源码自编译，
> DDR 参数天然匹配 SoC，不混用任何厂商二进制，从根上规避「loader 不匹配导致不开机」。

## 编译

手动触发 `Zero2-ALL` workflow（Actions → Zero2-ALL → Run workflow）：

- `CONFIGS`：JSON 数组，默认 `["RK3528-ZERO2-FULL"]`
- `TEST=true`：仅输出 `.config` 不编译（约 5 分钟，用于验证配置）
- 产物自动传到 Releases

## 刷机（防变砖）

**核心认知：刷 TF 卡永远不会烧板子。** Zero2 的 BootROM 启动顺序是
**SPI NOR → SD → eMMC**，只要卡里有固件就从卡启动，eMMC 内容零改动。

分三阶段，每阶段都有回头路：

```
阶段 1（零风险）仅刷 TF 卡
  └─ 全程不碰 eMMC，随时拔卡回原系统
  └─ 验证：串口 1500000bps 有输出 / 千兆网通 / 能进 LuCI

阶段 2（低风险）验证通过后再写 eMMC
  └─ TF 卡保留不拔，写坏插卡照样启动
  └─ 验证：拔卡后能从 eMMC 独立启动

阶段 3（兜底）Maskrom 救砖
  └─ 按住 MASK 键上电 → USB-C 接电脑 → RKDevTool / upgrade_tool 重刷
  └─ SoC 内部固化协议，任何存储写坏都能救
```

## Open-Box（已集成，无需手动安装）

**Open-Box 组件已预置在固件内，刷完即用，无需联网。**

四个组件（app / runtime / kernel / geo，约 75MB）在编译期下载、SHA256 校验后
打包进 rootfs 的 `/usr/share/open-box-bundle/`。

### 首次启动自动部署

路由器**第一次开机**会自动：

```
① 在系统盘剩余空间新建分区，格式化为 ext4，挂载到 /opt
② 重启一次（内核需重读分区表）
③ 第二次开机：把 bundle 铺到 /opt/open-box，装好 init.d 服务与 LuCI 入口
```

> 首次开机因涉及新分区识别，会**自动重启一次**，属正常现象。

### 使用

- 浏览器打开 `http://<路由器IP>:3036`，**首次访问设置面板密码**
- LuCI 里也有入口：服务 → Open-Box（面板打不开时可在此启停/恢复直连）
- 忘记密码：SSH 执行 `open-box` 选 `1`，或直接 `open-box password`

### 关于升级

固件内置的是打包时的版本（当前 `v0.1.287`）。
Open-Box 自身升级走它自己的通道，不影响固件：

```sh
curl -fsSL https://raw.githubusercontent.com/liandu2024/Open-Box/main/scripts/update.sh | sh
```

### 为什么不用官方 install.sh

官方脚本检测到 `/opt/open-box` 已存在会**拒绝安装**，而 `/opt` 是运行时挂载的
独立分区，编译期写入的内容会被覆盖。因此采用「预置到 rootfs bundle → 首启铺到 /opt」
的方式绕开该限制。

## ⚠️ 旁路由必读

作为旁路由使用时（终端网关 / DNS 指向本机），**必须打开 LAN 区域的「IP 动态伪装」（MASQUERADE）**。

> 否则直连站点的回包不经旁路由、连接对不上，表现为
> **只能上国外、打不开大陆网站**。

LuCI 路径：网络 → 防火墙 → 区域 → lan → 勾选「IP 动态伪装」→ 保存应用。

本固件**不预置**旁路由参数（LAN 静态 IP、关 DHCP、masquerade 等），需自行配置。


**唯一不可逆的是写 OTP 熔丝**——正常刷机流程不会碰到。

- 默认登录：`192.168.10.1` / root / `password`

## 目录结构

```
Config/
  RK3528-ZERO2-FULL.txt   # 设备平台 + 分区 + Open-Box 依赖 + 无线裁剪
  GENERAL.txt             # 通用软件包集合
Scripts/
  Inject-ZERO2.sh         # 注入 board.d 网口/LED 映射
  Packages.sh             # 第三方包源管理
  Handles.sh              # 包裁剪与替换
  Settings.sh             # 默认 IP/主机名/主题/时区/密码
.github/workflows/
  Zero2-ALL.yml           # 编译入口（手动/自动触发）
  WRT-CORE.yml            # 云编译核心（公用）
  Auto-Clean.yml          # 定期清理
  Cache-Clean.yml         # 缓存清理
```

## 参考

- 官方规格：https://wiki.friendlyelec.com/wiki/index.php/NanoPi_Zero2/zh
- 官方救砖：同上 →「11 救砖办法」
- 姊妹仓库（NanoPi R28S）：https://github.com/sy3tem/ImmortalWrt-R28S
