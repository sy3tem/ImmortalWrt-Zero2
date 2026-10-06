#!/bin/bash
# SPDX-License-Identifier: MIT
# 将 Open-Box 组件预置进 ImmortalWrt 固件(离线可用, 刷完即用)
#
# 设计要点:
#   1) 组件不放进 rootfs 的 /opt —— /opt 在运行时是独立大分区, 编译期写进去会被覆盖.
#      改为放到 rootfs 的 /usr/share/open-box-bundle/, 首启由 init.d 铺到 /opt/open-box.
#   2) 不调用 Open-Box 官方 install.sh —— 它检测到 /opt/open-box 已存在会拒绝安装.
#      我们只取其组件包(tar.gz), 自建目录结构 + 自建 init.d/LuCI 文件.
#   3) 组件带 SHA256 校验(取自 components.json), 校验失败则中止编译, 不带坏包进固件.
#
# 调用时机: WRT-CORE 的 "Custom Packages" 阶段(有网络, 能下载 Release 资产)

set -e

OB_VERSION="v0.1.287"
OB_REPO="liandu2024/Open-Box"
OB_ARCH="arm64"
WORK="$GITHUB_WORKSPACE/.openbox-build"

echo "===== Fetch Open-Box ${OB_VERSION} (${OB_ARCH}) ====="

# ---- 1) 下载四个组件包 ----
mkdir -p "$WORK"
cd "$WORK"

for c in app runtime kernel geo; do
	ASSET="open-box-${OB_VERSION}-linux-${OB_ARCH}-${c}.tar.gz"
	if [ ! -f "$ASSET" ]; then
		echo "[dl] $ASSET"
		curl -fsSL --retry 3 --connect-timeout 20 \
			"https://github.com/${OB_REPO}/releases/download/${OB_VERSION}/${ASSET}" \
			-o "$ASSET"
	fi
done
ls -lh *.tar.gz

# ---- 2) SHA256 校验(硬编码, 与 components.json 一致) ----
echo "[verify] SHA256"
verify() {
	local file="$1" want="$2"
	local got
	got=$(sha256sum "$file" | awk '{print $1}')
	if [ "$got" != "$want" ]; then
		echo "FATAL: $file SHA256 不匹配" >&2
		echo "  want: $want" >&2
		echo "  got : $got" >&2
		exit 1
	fi
	echo "  ok  $file"
}
verify "open-box-${OB_VERSION}-linux-${OB_ARCH}-app.tar.gz"     "89b36ec590dfd92a818c1cf85bb2c1773a6a76b3cb8241aabd983f4225f17134"
verify "open-box-${OB_VERSION}-linux-${OB_ARCH}-runtime.tar.gz" "399fa1ab426f44428284f3dc3ddbcf3e10de054f56c106ceb825c490bb0a8f49"
verify "open-box-${OB_VERSION}-linux-${OB_ARCH}-kernel.tar.gz"  "36b7a734d461dde1e9ccef87cd1c301218032b112f5fa7c2967455433085927f"
verify "open-box-${OB_VERSION}-linux-${OB_ARCH}-geo.tar.gz"     "282acf50f7a2d73bae3c6a3803e2f0e239bc401854bd1d61be5459031f414c31"

# ---- 3) 解包到 bundle 目录 ----
echo "[extract] -> bundle"
BUNDLE="$WORK/bundle"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE"

for c in app runtime kernel geo; do
	ASSET="open-box-${OB_VERSION}-linux-${OB_ARCH}-${c}.tar.gz"
	tar -xzf "$ASSET" -C "$BUNDLE"
	echo "  extracted $c"
done

echo "[bundle] 内容:"
find "$BUNDLE" -maxdepth 2 | head -30
du -sh "$BUNDLE"

# ---- 4) 铺进源码树 target 文件目录(rootfs 内路径) ----
# 注意: 用 target/linux/rockchip/armv8/base-files/ 而非 package/base-files,
#       避免污染其它平台(该目录只对本平台生效)
RK_BF="./target/linux/rockchip/armv8/base-files"
DEST="$RK_BF/usr/share/open-box-bundle"
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -a "$BUNDLE" "$DEST"
echo "[4] bundle 已铺入 $DEST"
du -sh "$DEST"

echo "===== Open-Box bundle 准备完成 ====="
