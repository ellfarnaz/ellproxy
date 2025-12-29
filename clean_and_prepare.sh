#!/bin/bash

# clean_and_prepare.sh
# Automates the cleanup of dev logs and prepares a fresh production build.

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Release Preparation...${NC}"

# 1. Cleanup Logs and Validation Data
echo -e "${BLUE}🧹 Cleaning up development artifacts...${NC}"
rm -rf batch_reasoning_validation/
rm -f *.json
rm -f scripts/*.json
echo -e "${GREEN}✅ Development logs and test outputs removed.${NC}"

# 2. Build Cleanup
echo -e "${BLUE}🔨 Cleaning build cache...${NC}"
make clean
echo -e "${GREEN}✅ Build cache cleared.${NC}"

# 3. Security Audit (Config)
echo -e "${BLUE}🔒 Auditing config files for sensitive keys...${NC}"
CONFIG_FOUND=false
for cfg in "src/Sources/Resources/config.yaml" "src/Sources/App/Config/config.yaml" "config.yaml"; do
    if [ -f "$cfg" ]; then
        CONFIG_FOUND=true
        if grep -q "sk-" "$cfg"; then
            echo -e "${YELLOW}⚠️ WARNING: OpenAI-style keys (sk-...) found in $cfg!${NC}"
        else
            echo -e "${GREEN}✅ No sensitive OpenAI keys detected in $cfg.${NC}"
        fi
    fi
done

if [ "$CONFIG_FOUND" = false ]; then
    echo -e "${YELLOW}⚠️ No config.yaml found to audit.${NC}"
fi

# 4. Automate Binary Update
echo -e "${BLUE}⬇️ Updating CLIProxyAPIPlus binary to latest version...${NC}"
if [ -f "scripts/update_binary.sh" ]; then
    chmod +x scripts/update_binary.sh
    ./scripts/update_binary.sh
else
    echo -e "${YELLOW}⚠️ scripts/update_binary.sh not found, skipping binary update.${NC}"
fi

# 5. Final Build
echo -e "${BLUE}📦 Starting fresh production build...${NC}"
make app

echo -e ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}🎉 PREPARATION COMPLETE!${NC}"
echo -e "${GREEN}Final App: EllProxy.app${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e ""
echo -e "${YELLOW}Next Step: Zip EllProxy.app and upload to GitHub Releases.${NC}"
