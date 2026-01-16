# !/bin/bash
set -e

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
BUILD_DIR="build"
OUTPUT_DIR="$BUILD_DIR/output"

echo "🧹 清理旧构建..."
rm -rf "$BUILD_DIR"

echo "🔨 开始构建..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

echo "📦 准备输出目录..."
mkdir -p "$OUTPUT_DIR"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/Light Stats.app" "$OUTPUT_DIR/"

echo "✅ 构建完成！"
echo "📍 输出位置: $OUTPUT_DIR/Light Stats.app"
echo ""
echo "安装到 Applications 目录："
echo "  cp -R \"$OUTPUT_DIR/Light Stats.app\" /Applications/"

运行脚本：
chmod +x build.sh
./build.sh