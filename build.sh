#!/bin/bash
set -e

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
APP_NAME="Light Stats"

# 版本号优先级: 环境变量 > git tag > 默认值
if [ -n "$VERSION" ]; then
    echo "📌 使用环境变量版本号: $VERSION"
elif git describe --tags --exact-match 2>/dev/null; then
    VERSION=$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//')
    echo "📌 使用 git tag 版本号: $VERSION"
else
    VERSION="1.0.0-dev"
    echo "📌 使用默认版本号: $VERSION"
fi
BUILD_DIR="build"
OUTPUT_DIR="$BUILD_DIR/output"
LOG_FILE="$BUILD_DIR/build.log"
DMG_DIR="$BUILD_DIR/dmg_temp"
DMG_FILE="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"

echo "🔍 检查 Xcode 环境..."
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误: 未找到 xcodebuild 命令。请确保已安装 Xcode 并设置了命令行工具。"
    exit 1
fi
xcodebuild -version
echo ""

echo "🧹 清理旧构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "🔨 开始构建 (详细日志详见 $LOG_FILE)..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO > "$LOG_FILE" 2>&1

echo "📦 创建输出目录..."
mkdir -p "$OUTPUT_DIR"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$OUTPUT_DIR/"

# 确保可执行文件有执行权限
chmod +x "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "✅ App 构建完成！"
echo "📍 App 位置: $OUTPUT_DIR/$APP_NAME.app"
echo ""

echo "📀 开始创建 DMG 安装包..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

cp -R "$OUTPUT_DIR/$APP_NAME.app" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_FILE"

rm -rf "$DMG_DIR"

echo ""
echo "✅ 全部完成！"
echo "📍 App 位置: $OUTPUT_DIR/$APP_NAME.app"
echo "📍 DMG 位置: $DMG_FILE"
echo "📋 DMG 大小: $(du -h "$DMG_FILE" | cut -f1)"