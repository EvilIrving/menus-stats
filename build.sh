# !/bin/bash
set -e

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
BUILD_DIR="build"
OUTPUT_DIR="$BUILD_DIR/output"
LOG_FILE="$BUILD_DIR/build.log"

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
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/Light Stats.app" "$OUTPUT_DIR/"

echo "✅ 构建完成！"
echo "📍 输出位置: $OUTPUT_DIR/Light Stats.app"
# echo ""
# echo "安装到 Applications 目录："
# echo "  cp -R \"$OUTPUT_DIR/Light Stats.app\" /Applications/"