#!/usr/bin/env bash
# 本地打包脚本：在 macOS 上生成未签名的 .ipa（给 TrollStore / 自签用）。
# 用法：./Scripts/build-ipa.sh [版本号]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "缺少 xcodegen，请先执行：brew install xcodegen"
  exit 1
fi

echo "==> 生成 Xcode 工程"
xcodegen generate --spec project.yml

echo "==> 编译（Release，不签名）"
xcodebuild \
  -project DaidaiPanel.xcodeproj \
  -scheme DaidaiPanel \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="build/Build/Products/Release-iphoneos/DaidaiPanel.app"
IPA_NAME="DaidaiPanel-iOS-${VERSION}-unsigned.ipa"

echo "==> 打包 $IPA_NAME"
rm -rf Payload
mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry "$IPA_NAME" Payload
rm -rf Payload

echo "==> 完成：$(pwd)/$IPA_NAME"
