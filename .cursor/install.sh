#!/usr/bin/env bash
# 幂等安装脚本：为「不能断」核心逻辑包准备 Swift 工具链并构建。
# 产品是 iOS App，但核心领域逻辑（数据模型 + 结算 + 补签卡）不依赖 UIKit/UserNotifications，
# 可用 Swift on Linux 通过 SwiftPM 构建与单测。
set -euo pipefail

SWIFT_VERSION="6.1.2"
SWIFT_DIR="/opt/swift"
SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"

export DEBIAN_FRONTEND=noninteractive

# 1) Swift 运行/构建所需系统依赖。
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
  binutils gnupg2 libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev \
  libpython3-dev libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata \
  zlib1g-dev libncurses-dev python3 curl ca-certificates

# 2) Swift 工具链（已存在则跳过，保证幂等）。
if [ ! -x "${SWIFT_DIR}/usr/bin/swift" ]; then
  echo "Installing Swift ${SWIFT_VERSION} ..."
  tmp="$(mktemp -d)"
  curl -fL --retry 4 --retry-delay 4 -o "${tmp}/swift.tar.gz" "${SWIFT_URL}"
  sudo rm -rf "${SWIFT_DIR}"
  sudo mkdir -p "${SWIFT_DIR}"
  sudo tar xzf "${tmp}/swift.tar.gz" -C "${SWIFT_DIR}" --strip-components=1
  rm -rf "${tmp}"
else
  echo "Swift already present at ${SWIFT_DIR}, skipping download."
fi

# 3) 让任意 shell 都能找到 swift（登录 shell 走 profile.d，非登录 shell 走 wrapper）。
echo 'export PATH=/opt/swift/usr/bin:$PATH' | sudo tee /etc/profile.d/swift.sh >/dev/null
sudo chmod 0644 /etc/profile.d/swift.sh
printf '#!/bin/sh\nexec /opt/swift/usr/bin/swift "$@"\n' | sudo tee /usr/local/bin/swift >/dev/null
printf '#!/bin/sh\nexec /opt/swift/usr/bin/swiftc "$@"\n' | sudo tee /usr/local/bin/swiftc >/dev/null
sudo chmod 0755 /usr/local/bin/swift /usr/local/bin/swiftc

export PATH="${SWIFT_DIR}/usr/bin:${PATH}"

# 4) 解析依赖并构建，验证工作区可用。
swift --version
swift build

echo "install.sh completed."
