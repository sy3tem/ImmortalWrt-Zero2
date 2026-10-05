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
- **代理**：passwall + xray-core
- **附加**：argon 主题、iStore、dockerman、ttyd、turboacc 等（见 `Config/GENERAL.txt`）

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

**唯一不可逆的是写 OTP 熔丝**——正常刷机流程不会碰到。

- 默认登录：`192.168.10.1` / root / `password`

## 目录结构

```
Config/
  RK3528-ZERO2-FULL.txt   # 设备平台 + 分区 + 代理插件
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
