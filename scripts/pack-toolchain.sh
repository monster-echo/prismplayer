#!/bin/bash
# 打包 DevEco Studio 内置 HarmonyOS 工具链(裁剪版),供 GitHub macos-15 runner 构建。
# 镜像仓库: https://github.com/monster-echo/harmonyos-cli (public,多项目共用)
#
# 裁剪说明(相对 DevEco 完整安装 ~7.6G):
#   - tools/node    : runner 用 actions/setup-node 装 Node 24,省 939M
#   - */previewer   : assembleHap/assembleApp 不需要预览器,省 ~820M
#   - hms/native    : 工程 CMake 链接的全部 NDK 库都在 openharmony/native,
#                     hms/native(HMS NDK)用不到,省 1.8G
# 保留 ~3.4G:gzip 后约 1.5-1.9G,按 1900M 分卷以适配 GitHub release 单文件 2GB 上限。
#
# 用法:
#   ./scripts/pack-toolchain.sh                 # 只打包到 ~/Downloads
#   UPLOAD=1 ./scripts/pack-toolchain.sh        # 打包并上传到镜像仓库 release
#
# 上传后同步修改各项目 workflow 里的 env.TOOLCHAIN_VERSION,两边保持一致。

set -euo pipefail

DEVECO_APP="/Applications/DevEco-Studio.app"
REPO="${REPO:-monster-echo/harmonyos-cli}"
# SDK 实际版本可从 Contents/sdk/default/sdk-pkg.json 的 "version" 读取,尾部 -N 为打包序号:
# 工具链有任何变化(升级 DevEco、增删目录)时递增 -N,避免 CI 命中旧缓存。
TOOLCHAIN_VERSION="26.0.0.105-1"
OUT_DIR="${OUT_DIR:-$HOME/Downloads}"

SRC="$DEVECO_APP/Contents"
SDK_VERSION=$(python3 -c "import json;print(json.load(open('$SRC/sdk/default/sdk-pkg.json'))['data']['version'])" 2>/dev/null || echo "unknown")
echo "DevEco: $DEVECO_APP (sdk-pkg version: $SDK_VERSION)"

WORK=$(mktemp -d /tmp/harmony-cli-pack.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/harmony-cli/tools" "$WORK/harmony-cli/sdk"

echo "[1/4] 复制 tools(hvigor + ohpm)..."
ditto "$SRC/tools/hvigor" "$WORK/harmony-cli/tools/hvigor"
ditto "$SRC/tools/ohpm"   "$WORK/harmony-cli/tools/ohpm"

echo "[2/4] 复制 SDK 并裁剪(previewer、hms/native)..."
ditto "$SRC/sdk/default/openharmony" "$WORK/harmony-cli/sdk/default/openharmony"
ditto "$SRC/sdk/default/hms"         "$WORK/harmony-cli/sdk/default/hms"
rm -rf "$WORK/harmony-cli/sdk/default/openharmony/previewer"
rm -rf "$WORK/harmony-cli/sdk/default/hms/previewer"
rm -rf "$WORK/harmony-cli/sdk/default/hms/native"

echo "$TOOLCHAIN_VERSION" > "$WORK/harmony-cli/toolchain-version"
echo "  裁剪后体积: $(du -sh "$WORK/harmony-cli" | cut -f1)"

echo "[3/4] 打包 tar.gz..."
TARBALL="$OUT_DIR/harmony-cli-mac-$TOOLCHAIN_VERSION.tar.gz"
mkdir -p "$OUT_DIR"
tar -C "$WORK" -czf "$TARBALL" harmony-cli
TARBALL_SIZE=$(stat -f%z "$TARBALL")
echo "  $TARBALL ($(( TARBALL_SIZE / 1024 / 1024 )) MB)"

echo "[4/4] 按 1900M 分卷..."
rm -f "$TARBALL".part-*
split -b 1900m "$TARBALL" "$TARBALL.part-"
rm -f "$TARBALL"
PARTS=$(ls "$TARBALL".part-* | tr '\n' ' ')
echo "  分卷: $PARTS"

if [[ "${UPLOAD:-0}" == "1" ]]; then
  TAG="toolchain-$TOOLCHAIN_VERSION"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "release $TAG 已存在,直接追加 assets"
  else
    gh release create "$TAG" --repo "$REPO" \
      --title "HarmonyOS CLI toolchain $TOOLCHAIN_VERSION" \
      --notes "DevEco Studio 26.0.0 内置工具链裁剪版(hvigor/ohpm + SDK, 去 previewer/hms-native/node)。多项目 CI 共用,下载后 cat 分卷合并再解包。" \
      --latest=false
  fi
  for p in $PARTS; do
    gh release upload "$TAG" "$p" --repo "$REPO" --clobber
  done
  echo "上传完成。记得同步修改 workflow 的 TOOLCHAIN_VERSION=$TOOLCHAIN_VERSION"
else
  echo "未上传。手动上传:"
  echo "  UPLOAD=1 $0"
fi
