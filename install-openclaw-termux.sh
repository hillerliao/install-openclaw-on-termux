#!/bin/bash

# ==========================================
# Openclaw Termux 极简一键部署脚本 v2.0
# ==========================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

clear
echo -e "${BLUE}=========================================="
echo -e "   🦞 Openclaw Termux 零门槛部署工具"
echo -e "==========================================${NC}"

# --- 核心优化：自愈环境检查 ---
echo -e "${YELLOW}🔍 正在检查基础运行环境...${NC}"

# 定义需要的基础包
DEPS=("nodejs" "git" "openssh" "tmux" "termux-api")
MISSING_DEPS=()

for dep in "${DEPS[@]}"; do
    if ! command -v $dep &> /dev/null; then
        MISSING_DEPS+=($dep)
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${YELLOW}补充安装缺失组件: ${MISSING_DEPS[*]}...${NC}"
    pkg update -y && pkg upgrade -y
    pkg install ${MISSING_DEPS[*]} -y
else
    echo -e "${GREEN}✅ 基础环境已就绪${NC}"
fi

# --- 交互配置 ---
read -p "请输入 Gateway 端口号 [默认: 18789]: " PORT
PORT=${PORT:-18789}

read -p "是否需要开启开机自启动? (y/n) [默认: y]: " AUTO_START
AUTO_START=${AUTO_START:-y}

# --- 路径与安装 ---
echo -e "\n${YELLOW}🏗️  正在配置 Openclaw...${NC}"

# 配置 NPM 全局环境
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
grep -qxF 'export PATH=$HOME/.npm-global/bin:$PATH' ~/.bashrc || echo 'export PATH=$HOME/.npm-global/bin:$PATH' >> ~/.bashrc
export PATH=$HOME/.npm-global/bin:$PATH

# 安装 Openclaw (静默安装)
npm i -g openclaw > /dev/null 2>&1

BASE_DIR="$HOME/.npm-global/lib/node_modules/openclaw"
LOG_DIR="$HOME/openclaw-logs"
mkdir -p "$LOG_DIR" "$HOME/tmp"

# --- 补丁植入 ---
echo -e "${YELLOW}🛠️  正在应用 Android 兼容性补丁...${NC}"

# 修复 Logger
LOGGER_FILE="$BASE_DIR/dist/logging/logger.js"
if [ -f "$LOGGER_FILE" ]; then
    node -e "const fs = require('fs'); const file = '$LOGGER_FILE'; let c = fs.readFileSync(file, 'utf8'); c = c.replace(/\/tmp\/openclaw/g, process.env.HOME + '/openclaw-logs'); fs.writeFileSync(file, c);"
fi

# 修复剪贴板
CLIP_FILE="$BASE_DIR/node_modules/@mariozechner/clipboard/index.js"
if [ -f "$CLIP_FILE" ]; then
    node -e "const fs = require('fs'); const file = '$CLIP_FILE'; const mock = 'module.exports = { availableFormats:()=>[], getText:()=>\"\", setText:()=>false, hasText:()=>false, getImageBinary:()=>null, getImageBase64:()=>null, setImageBinary:()=>false, setImageBase64:()=>false, hasImage:()=>false, getHtml:()=>\"\", setHtml:()=>false, hasHtml:()=>false, getRtf:()=>\"\", setRtf:()=>false, hasRtf:()=>false, clear:()=>{}, watch:()=>({stop:()=>{}}), callThreadsafeFunction:()=>{} };'; fs.writeFileSync(file, mock);"
fi

# --- 启动逻辑 ---
if [ "$AUTO_START" == "y" ]; then
    sed -i '/# --- Openclaw Start ---/,/# --- Openclaw End ---/d' ~/.bashrc
    cat << EOT >> ~/.bashrc
# --- Openclaw Start ---
export TERMUX_VERSION=1
export TMPDIR=\$HOME/tmp
export PATH=\$HOME/.npm-global/bin:\$PATH
sshd 2>/dev/null
termux-wake-lock 2>/dev/null
tmux has-session -t openclaw 2>/dev/null || tmux new -d -s openclaw "openclaw gateway --port $PORT --allow-unconfigured"
# --- Openclaw End ---
EOT
fi

# 激活
termux-wake-lock 2>/dev/null
source ~/.bashrc 2>/dev/null

echo -e "\n${GREEN}=========================================="
echo -e "🎉 部署成功！"
echo -e "==========================================${NC}"
echo -e "📱 手机 IP: ${BLUE}$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1)${NC}"
echo -e "🚀 运行日志: ${GREEN}tmux attach -t openclaw${NC}"
echo -e "------------------------------------------"