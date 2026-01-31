#!/bin/bash
# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================
#
# Usage: curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh [options]
#
# Options:
#   --help, -h       Show help information
#   --verbose, -v    Enable verbose output (shows command execution details)
#   --dry-run, -d    Dry run mode (simulate execution without making changes)
#   --uninstall, -u  Uninstall Openclaw and clean up configurations
#
# Examples:
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh --verbose
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh --dry-run
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && bash openclaw-install.sh --uninstall
#
# Note: For direct local execution, use: bash install-openclaw-termux.sh [options]
#
# ==========================================

set -e
set -o pipefail

# 解析命令行选项
VERBOSE=0
DRY_RUN=0
UNINSTALL=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --dry-run|-d)
            DRY_RUN=1
            shift
            ;;
        --uninstall|-u)
            UNINSTALL=1
            shift
            ;;
        --help|-h)
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --verbose, -v    启用详细输出"
            echo "  --dry-run, -d    模拟运行，不执行实际命令"
            echo "  --uninstall, -u  卸载 Openclaw 和相关配置"
            echo "  --help, -h       显示此帮助信息"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

trap 'echo -e "${RED}错误：脚本执行失败，请检查上述输出${NC}"; exit 1' ERR

# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================

# Function definitions
check_deps() {
    # Check and install basic dependencies
    log "开始检查基础环境"
    echo -e "${YELLOW}[1/6] 正在检查基础运行环境...${NC}"

    # 检查是否需要更新 pkg（每天只执行一次）
    UPDATE_FLAG="$HOME/.pkg_last_update"
    if [ ! -f "$UPDATE_FLAG" ] || [ $(($(date +%s) - $(stat -c %Y "$UPDATE_FLAG" 2>/dev/null || echo 0))) -gt 86400 ]; then
        log "执行 pkg update"
        echo -e "${YELLOW}更新包列表...${NC}"
        run_cmd pkg update -y
        if [ $? -ne 0 ]; then
            log "pkg update 失败"
            echo -e "${RED}错误：pkg 更新失败${NC}"
            exit 1
        fi
        run_cmd touch "$UPDATE_FLAG"
        log "pkg update 完成"
    else
        log "跳过 pkg update（已更新）"
        echo -e "${GREEN}包列表已是最新${NC}"
    fi

    # 定义需要的基础包
    DEPS=("nodejs" "git" "openssh" "tmux" "termux-api" "termux-tools" "cmake" "python" "golang" "which")
    MISSING_DEPS=()

    for dep in "${DEPS[@]}"; do
        cmd=$dep
        if [ "$dep" = "nodejs" ]; then cmd="node"; fi
        if ! command -v $cmd &> /dev/null; then
            MISSING_DEPS+=($dep)
        fi
    done

    log "Node.js 版本: $(node --version 2>/dev/null || echo '未知')"
    echo -e "${BLUE}Node.js 版本: $(node -v)${NC}"
    echo -e "${BLUE}NPM 版本: $(npm -v)${NC}" 

    # 检查 Node.js 版本（必须 22 以上）
    NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" -lt 22 ]; then
        log "Node.js 版本检查失败: $NODE_VERSION"
        echo -e "${RED}错误：Node.js 版本必须 22 以上，当前版本: $(node --version 2>/dev/null || echo '未知')${NC}"
        exit 1
    fi
    log "Node.js 版本检查通过"

    touch "$BASHRC" 2>/dev/null

    log "设置 NPM 镜像"
    npm config set registry https://registry.npmmirror.com
    if [ $? -ne 0 ]; then
        log "NPM 镜像设置失败"
        echo -e "${RED}错误：NPM 镜像设置失败${NC}"
        exit 1
    fi

    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        log "缺失依赖: ${MISSING_DEPS[*]}"
        echo -e "${YELLOW}检查可能的组件缺失: ${MISSING_DEPS[*]}${NC}"
        run_cmd pkg upgrade -y
        if [ $? -ne 0 ]; then
            log "pkg upgrade 失败"
            echo -e "${RED}错误：pkg 升级失败${NC}"
            exit 1
        fi
        run_cmd pkg install ${MISSING_DEPS[*]} -y
        if [ $? -ne 0 ]; then
            log "依赖安装失败"
            echo -e "${RED}错误：依赖安装失败${NC}"
            exit 1
        fi
        log "依赖安装完成"
    else
        log "所有依赖已安装"
        echo -e "${GREEN}✅ 基础环境已就绪${NC}"
    fi
}

configure_npm() {
    # Configure NPM environment and install Openclaw
    log "开始配置 NPM"
    echo -e "\n${YELLOW}[2/6] 正在配置 Openclaw...${NC}"

    # 配置 NPM 全局环境
    mkdir -p "$NPM_GLOBAL"
    npm config set prefix "$NPM_GLOBAL"
    if [ $? -ne 0 ]; then
        log "NPM 前缀设置失败"
        echo -e "${RED}错误：NPM 前缀设置失败${NC}"
        exit 1
    fi
    grep -qxF "export PATH=$NPM_BIN:$PATH" "$BASHRC" || echo "export PATH=$NPM_BIN:$PATH" >> "$BASHRC"
    export PATH="$NPM_BIN:$PATH"

    if [ -f "$NPM_BIN/openclaw" ]; then
        log "Openclaw 已安装，跳过安装"
        echo -e "${GREEN}✅ Openclaw 已安装，跳过安装${NC}"
    else
        log "开始安装 Openclaw"
        # 安装 Openclaw (静默安装)
        run_cmd npm i -g openclaw
        if [ $? -ne 0 ]; then
            log "Openclaw 安装失败"
            echo -e "${RED}错误：Openclaw 安装失败${NC}"
            exit 1
        fi
        log "Openclaw 安装完成"
    fi

    BASE_DIR="$NPM_GLOBAL/lib/node_modules/openclaw"
    mkdir -p "$LOG_DIR" "$HOME/tmp"
    if [ $? -ne 0 ]; then
        log "目录创建失败"
        echo -e "${RED}错误：目录创建失败${NC}"
        exit 1
    fi
}

apply_patches() {
    # Apply Android compatibility patches
    log "开始应用补丁"
    echo -e "${YELLOW}[3/6] 正在应用 Android 兼容性补丁...${NC}"

    # 修复 Logger
    LOGGER_FILE="$BASE_DIR/dist/logging/logger.js"
    if [ -f "$LOGGER_FILE" ]; then
        log "应用 Logger 补丁"
        node -e "const fs = require('fs'); const file = '$LOGGER_FILE'; let c = fs.readFileSync(file, 'utf8'); c = c.replace(/\/tmp\/openclaw/g, process.env.HOME + '/openclaw-logs'); fs.writeFileSync(file, c);"
        if [ $? -ne 0 ]; then
            log "Logger 补丁应用失败"
            echo -e "${RED}错误：Logger 补丁应用失败${NC}"
            exit 1
        fi
        # 验证补丁是否生效
        if grep -q "/tmp/openclaw" "$LOGGER_FILE"; then
            log "Logger 补丁验证失败"
            echo -e "${RED}错误：Logger 补丁未正确应用，请检查文件内容${NC}"
            exit 1
        fi
        log "Logger 补丁应用成功"
    fi

    # 修复剪贴板
    CLIP_FILE="$BASE_DIR/node_modules/@mariozechner/clipboard/index.js"
    if [ -f "$CLIP_FILE" ]; then
        log "应用剪贴板补丁"
        node -e "const fs = require('fs'); const file = '$CLIP_FILE'; const mock = 'module.exports = { availableFormats:()=>[], getText:()=>\"\", setText:()=>false, hasText:()=>false, getImageBinary:()=>null, getImageBase64:()=>null, setImageBinary:()=>false, setImageBase64:()=>false, hasImage:()=>false, getHtml:()=>\"\", setHtml:()=>false, hasHtml:()=>false, getRtf:()=>\"\", setRtf:()=>false, hasRtf:()=>false, clear:()=>{}, watch:()=>({stop:()=>{}}), callThreadsafeFunction:()=>{} };'; fs.writeFileSync(file, mock);"
        if [ $? -ne 0 ]; then
            log "剪贴板补丁应用失败"
            echo -e "${RED}错误：剪贴板补丁应用失败${NC}"
            exit 1
        fi
        # 验证补丁是否生效
        if ! grep -q "availableFormats" "$CLIP_FILE"; then
            log "剪贴板补丁验证失败"
            echo -e "${RED}错误：剪贴板补丁未正确应用，请检查文件内容${NC}"
            exit 1
        fi
        log "剪贴板补丁应用成功"
    fi
}

setup_autostart() {
    # Configure autostart and aliases
    if [ "$AUTO_START" == "y" ]; then
        log "配置自启动"
        # 备份原 ~/.bashrc 文件
        run_cmd cp "$BASHRC" "$BASHRC.backup"
        run_cmd sed -i '/# --- Openclaw Start ---/,/# --- Openclaw End ---/d' "$BASHRC"
        if [ $? -ne 0 ]; then
            log "bashrc 修改失败"
            echo -e "${RED}错误：bashrc 修改失败${NC}"
            exit 1
        fi
        cat << EOT >> "$BASHRC"
# --- Openclaw Start ---
# WARNING: This section contains your access token - keep ~/.bashrc secure
export TERMUX_VERSION=1
export TMPDIR=\$HOME/tmp
export OPENCLAW_TOKEN=$TOKEN
export PATH=\$NPM_BIN:\$PATH
sshd 2>/dev/null
termux-wake-lock 2>/dev/null
alias ocr="pkill -9 node 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null; sleep 1; tmux new -d -s openclaw; sleep 1; tmux send-keys -t openclaw \"export PATH=$NPM_BIN:$PATH TMPDIR=$HOME/tmp; openclaw gateway --bind lan --port $PORT --allow-unconfigured\" C-m"
alias oclog='tmux attach -t openclaw'
alias ockill='pkill -9 node 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null'
# --- OpenClaw End ---
EOT

        source "$BASHRC"
        if [ $? -ne 0 ]; then
            log "bashrc 加载警告"
            echo -e "${YELLOW}警告：bashrc 加载失败，可能影响别名${NC}"
        fi
        log "自启动配置完成"
    else
        log "跳过自启动配置"
    fi
}

activate_wakelock() {
    # Activate wake lock to prevent sleep
    log "激活唤醒锁"
    echo -e "${YELLOW}[4/6] 激活唤醒锁...${NC}"
    termux-wake-lock 2>/dev/null
    if [ $? -eq 0 ]; then
        log "唤醒锁激活成功"
        echo -e "${GREEN}✅ Wake-lock 已激活${NC}"
    else
        log "唤醒锁激活失败"
        echo -e "${YELLOW}⚠️  Wake-lock 激活失败，可能 termux-api 未正确安装${NC}"
    fi
}

start_service() {
    log "启动服务"
    echo -e "${YELLOW}[5/6] 启动服务...${NC}"

    # 1. 防止 pkill 报错导致脚本退出
    pkill -9 node 2>/dev/null || true
    tmux kill-session -t openclaw 2>/dev/null || true
    sleep 1

    # 2. 确保目录存在
    mkdir -p "$HOME/tmp"
    export TMPDIR="$HOME/tmp"

    # 3. 创建会话并捕获可能的错误
    # 这里我们先启动一个 shell，再在 shell 里执行命令，方便观察
    tmux new -d -s openclaw
    sleep 1
    
    # 将输出重定向到一个临时文件，如果 tmux 崩了也能看到报错
    tmux send-keys -t openclaw "export PATH=$NPM_BIN:$PATH TMPDIR=$HOME/tmp; openclaw gateway --bind lan --port $PORT --allow-unconfigured 2>&1 | tee $LOG_DIR/runtime.log" C-m
    
    log "服务指令已发送"
    echo -e "${GREEN}[6/6] 部署指令发送完毕${NC}"
    
    # 4. 实时验证
    sleep 2
    if tmux has-session -t openclaw 2>/dev/null; then
        echo -e "${GREEN}✅ tmux 会话已建立！${NC}"
        echo -e "请退出终端重新进入后执行: ${CYAN}oclog${NC} 查看日志"
    else
        echo -e "${RED}❌ 错误：tmux 会话启动后立即崩溃。${NC}"
        echo -e "请检查报错日志: ${YELLOW}cat $LOG_DIR/runtime.log${NC}"
    fi
}

uninstall_openclaw() {
    # Uninstall Openclaw and clean up configurations
    log "开始卸载 Openclaw"
    echo -e "${YELLOW}开始卸载 Openclaw...${NC}"

    # 停止服务
    echo -e "${YELLOW}停止服务...${NC}"
    run_cmd pkill -9 node 2>/dev/null || true
    run_cmd tmux kill-session -t openclaw 2>/dev/null || true
    log "服务已停止"

    # 删除别名和配置
    echo -e "${YELLOW}删除别名和配置...${NC}"
    run_cmd sed -i '/# --- Openclaw Start ---/,/# --- Openclaw End ---/d' "$BASHRC"
    run_cmd sed -i '/export PATH=.*\.npm-global\/bin/d' "$BASHRC"
    log "别名和配置已删除"

    # 恢复备份的 bashrc
    if [ -f "$BASHRC.backup" ]; then
        echo -e "${YELLOW}恢复原始 ~/.bashrc...${NC}"
        run_cmd cp "$BASHRC.backup" "$BASHRC"
        run_cmd rm "$BASHRC.backup"
        log "bashrc 已恢复"
    fi

    # 卸载 npm 包
    echo -e "${YELLOW}卸载 Openclaw 包...${NC}"
    run_cmd npm uninstall -g openclaw 2>/dev/null || true
    log "Openclaw 包已卸载"

    # 删除日志和配置目录
    echo -e "${YELLOW}删除日志和配置目录...${NC}"
    run_cmd rm -rf "$LOG_DIR" 2>/dev/null || true
    run_cmd rm -rf "$NPM_GLOBAL" 2>/dev/null || true
    log "日志和配置目录已删除"

    # 删除更新标志
    run_cmd rm -f "$HOME/.pkg_last_update" 2>/dev/null || true

    echo -e "${GREEN}卸载完成！${NC}"
    log "卸载完成"
}

# 主脚本

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 检查终端是否支持颜色
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    : # 支持，保持颜色
else
    GREEN=''
    BLUE=''
    YELLOW=''
    RED=''
    NC=''
fi

# 定义常用路径变量
BASHRC="$HOME/.bashrc"
NPM_GLOBAL="$HOME/.npm-global"
NPM_BIN="$NPM_GLOBAL/bin"
LOG_DIR="$HOME/openclaw-logs"
LOG_FILE="$LOG_DIR/install.log"

# 日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# 命令执行函数（支持 dry-run）
run_cmd() {
    if [ $VERBOSE -eq 1 ]; then
        echo "[VERBOSE] 执行: $@"
    fi
    log "执行命令: $@"
    if [ $DRY_RUN -eq 1 ]; then
        echo "[DRY-RUN] 跳过: $@"
        return 0
    else
        "$@"
    fi
}

clear
if [ $DRY_RUN -eq 1 ]; then
    echo -e "${YELLOW}🔍 模拟运行模式：不执行实际命令${NC}"
fi
if [ $VERBOSE -eq 1 ]; then
    echo -e "${BLUE}详细输出模式已启用${NC}"
fi
echo -e "${BLUE}=========================================="
echo -e "   🦞 Openclaw Termux 部署工具"
echo -e "==========================================${NC}"

# --- 交互配置 ---
read -p "请输入 Gateway 端口号 [默认: 18789]: " PORT
PORT=${PORT:-18789}

read -p "请输入自定义 Token (用于安全访问，建议强密码) [留空随机生成]: " TOKEN
if [ -z "$TOKEN" ]; then
    # 生成随机 Token
    RANDOM_PART=$(date +%s | md5sum | cut -c 1-8)
    TOKEN="token$RANDOM_PART"
    echo -e "${GREEN}生成的随机 Token: $TOKEN${NC}"
fi

read -p "是否需要开启开机自启动? (y/n) [默认: y]: " AUTO_START
AUTO_START=${AUTO_START:-y}

# 执行步骤
if [ $UNINSTALL -eq 1 ]; then
    uninstall_openclaw
    exit 0
fi

log "脚本开始执行，用户配置: 端口=$PORT, Token=$TOKEN, 自启动=$AUTO_START"
check_deps
configure_npm
apply_patches
setup_autostart
activate_wakelock
start_service
echo -e "${GREEN}脚本执行完成！${NC}，token为：$TOKEN  。常用命令：执行 oclog 查看运行状态； ockill 停止服务；ocr 重启服务。"
log "脚本执行完成"

