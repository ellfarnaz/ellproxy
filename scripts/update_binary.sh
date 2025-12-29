#!/bin/bash

# scripts/update_binary.sh
# Fetches the latest CLIProxyAPIPlus binary for Apple Silicon (darwin_arm64).

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

REPO="router-for-me/CLIProxyAPIPlus"
TARGET_DIR="src/Sources/Resources"
TARGET_FILE="$TARGET_DIR/cli-proxy-api-plus"

echo -e "${BLUE}🔍 Checking for latest release from $REPO...${NC}"

# Get latest tag and version
LATEST_JSON=$(curl -s -f "https://api.github.com/repos/$REPO/releases/latest")
TAG=$(echo "$LATEST_JSON" | jq -r .tag_name)
VERSION=${TAG#v}

if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
    echo -e "${RED}❌ Failed to fetch latest version info.${NC}"
    exit 1
fi

echo -e "${GREEN}✨ Found latest version: $VERSION ($TAG)${NC}"

FILENAME="CLIProxyAPIPlus_${VERSION}_darwin_arm64.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$FILENAME"

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${BLUE}⬇️ Downloading $FILENAME...${NC}"
if ! curl -L -o "$TEMP_DIR/$FILENAME" "$URL"; then
    echo -e "${RED}❌ Download failed.${NC}"
    exit 1
fi

echo -e "${BLUE}📦 Extracting binary...${NC}"
tar -xzf "$TEMP_DIR/$FILENAME" -C "$TEMP_DIR"

# Find the binary (usually named cli-proxy-api-plus or similar)
EXTRACTED_FILE=$(tar -tf "$TEMP_DIR/$FILENAME" | grep -E '^(cli-proxy-api-plus|CLIProxyAPIPlus)$' | head -n 1)

if [ -z "$EXTRACTED_FILE" ]; then
    # Fallback search if exact name not match
    EXTRACTED_FILE=$(ls "$TEMP_DIR" | grep -v -E '(LICENSE|README|\.md$|\.txt$|\.tar\.gz$)' | head -n 1)
fi

if [ -z "$EXTRACTED_FILE" ]; then
    echo -e "${RED}❌ Could not find binary in the package.${NC}"
    exit 1
fi

echo -e "${BLUE}🚀 Installing new binary to $TARGET_FILE...${NC}"
cp "$TEMP_DIR/$EXTRACTED_FILE" "$TARGET_FILE"
chmod +x "$TARGET_FILE"

echo -e "${GREEN}✅ Update successful! Binary is now version $VERSION.${NC}"
