#!/bin/bash
# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================
#
# Usage: curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh [options]
#
# Options:
#   --help, -h       Show help information
#   --verbose, -v    Enable verbose output (shows command execution details)
#   --dry-run, -d    Dry run mode (simulate execution without making changes)
#   --uninstall, -u  Uninstall Openclaw and clean up configurations
#   --update, -U     Force update Openclaw to latest version without prompting
#
# Examples:
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh --verbose
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh --dry-run
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh --uninstall
#   curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh --update
#
# Note: For direct local execution, use: source install-openclaw-termux.sh [options]
#
# ==========================================

# 注意：此脚本建议使用 source 方式执行，以便别名和环境变量立即生效
# 检测执行方式
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "⚠️  提示: 建议使用 source 方式执行，以便别名立即生效"
    echo "   执行: source $0 [选项]"
    echo ""
    read -p "继续使用 bash 方式执行? (y/n) [默认: y]: " CONTINUE_BASH
    CONTINUE_BASH=${CONTINUE_BASH:-y}
    if [[ "$CONTINUE_BASH" != "y" && "$CONTINUE_BASH" != "Y" ]]; then
        echo "已取消，请使用: source $0"
        exit 0
    fi
    echo ""
fi

# 解析命令行选项
VERBOSE=0
DRY_RUN=0
UNINSTALL=0
FORCE_UPDATE=0
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
        --update|-U)
            FORCE_UPDATE=1
            shift
            ;;
        --help|-h)
            echo "用法: source $0 [选项]"
            echo "选项:"
            echo "  --verbose, -v    启用详细输出"
            echo "  --dry-run, -d    模拟运行，不执行实际命令"
            echo "  --uninstall, -u  卸载 Openclaw 和相关配置"
            echo "  --update, -U     强制更新到最新版本"
            echo "  --help, -h       显示此帮助信息"
            echo ""
            echo "注意: 建议使用 source 方式执行，以便别名立即生效"
            exit 0
            ;;
        *)
            echo "未知选项: $1"
            echo "使用 --help 查看帮助"
            exit 1
            ;;
    esac
done

trap 'echo -e "${RED}错误：脚本执行失败，请检查上述输出${NC}"' ERR

# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================

# Function definitions

apply_koffi_stub() {
    # Apply koffi stub for Termux compatibility (android-arm64)
    # koffi is only used by pi-tui for Windows VT input, which never executes on Android
    log "应用 koffi stub"
    echo -e "${YELLOW}[2.5/6] 正在应用 koffi 兼容性修复...${NC}"
    
    KOFFI_DIR="$NPM_GLOBAL/lib/node_modules/openclaw/node_modules/koffi"
    
    if [ -d "$KOFFI_DIR" ]; then
        cat > "$KOFFI_DIR/index.js" << 'EOF'
// Koffi stub for android-arm64 — native module not available on this platform.
// koffi is only used by pi-tui for Windows VT input (enableWindowsVTInput),
// which is guarded by process.platform !== "win32" and never executes here.
const handler = {
  get(_, prop) {
    if (prop === '__esModule') return false;
    if (prop === 'default') return proxy;
    if (prop === 'then') return undefined;
    return function() { throw new Error('koffi stub: not available on android-arm64'); };
  }
};
const proxy = new Proxy({}, handler);
module.exports = proxy;
module.exports.default = proxy;
EOF
        log "koffi stub 应用成功"
        echo -e "${GREEN}✓ koffi stub 应用成功${NC}"
    else
        log "koffi 目录不存在，跳过 stub"
    fi
}

check_deps() {
    # Check and install basic dependencies
    log "开始检查基础环境"
    echo -e "${YELLOW}[1/6] 正在检查基础运行环境...${NC}"

    # 检查是否需要更新 pkg
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
    DEPS=("nodejs-lts" "git" "openssh" "tmux" "termux-api" "termux-tools" "cmake" "python" "golang" "which")
    MISSING_DEPS=()

    for dep in "${DEPS[@]}"; do
        cmd=$dep
        if [ "$dep" = "nodejs-lts" ]; then cmd="node"; fi
        if ! command -v $cmd &> /dev/null; then
            MISSING_DEPS+=($dep)
        fi
    done

    # 先安装缺失的依赖（包括 nodejs），再做版本检查
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

    # 依赖安装完毕后，显示版本信息
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
    
    # 警告：如果是 Node.js 25 (非 LTS)，提示可能遇到兼容性问题并提供降级选项
    if [ "$NODE_VERSION" -eq 25 ]; then
        log "警告：检测到 Node.js 25 (非 LTS 版本)"
        echo -e "${YELLOW}⚠️  警告：当前使用 Node.js 25 (Current 版本)，可能遇到原生模块兼容性问题${NC}"
        echo -e "${YELLOW}    建议降级到 Node.js 24 LTS 版本以获得更好的稳定性${NC}"
        echo ""
        read -p "是否降级到 Node.js 24 LTS? (y/n) [默认: y]: " DOWNGRADE_CHOICE
        DOWNGRADE_CHOICE=${DOWNGRADE_CHOICE:-y}
        
        if [ "$DOWNGRADE_CHOICE" = "y" ] || [ "$DOWNGRADE_CHOICE" = "Y" ]; then
            log "开始降级 Node.js 到 LTS 版本"
            echo -e "${YELLOW}正在降级 Node.js 到 24 LTS...${NC}"
            
            # 先卸载当前版本的 Node.js
            run_cmd pkg uninstall nodejs -y
            if [ $? -ne 0 ]; then
                log "Node.js 卸载失败"
                echo -e "${RED}错误：Node.js 卸载失败${NC}"
                exit 1
            fi
            
            # 安装 Node.js LTS 版本
            run_cmd pkg install nodejs-lts -y
            if [ $? -ne 0 ]; then
                log "Node.js LTS 安装失败"
                echo -e "${RED}错误：Node.js LTS 安装失败${NC}"
                exit 1
            fi
            
            # 重新获取 Node.js 版本
            NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
            echo -e "${GREEN}✅ Node.js 已降级到 $(node --version)${NC}"
            log "Node.js 降级完成: $(node --version)"
        else
            log "用户选择继续使用 Node.js 25"
            echo -e "${YELLOW}继续安装，但可能遇到兼容性问题${NC}"
            read -p "是否继续? (y/n) [默认: n]: " CONTINUE_INSTALL
            CONTINUE_INSTALL=${CONTINUE_INSTALL:-n}
            if [ "$CONTINUE_INSTALL" != "y" ] && [ "$CONTINUE_INSTALL" != "Y" ]; then
                log "用户选择退出安装"
                echo -e "${YELLOW}已取消安装${NC}"
                exit 0
            fi
        fi
    fi
    
    log "Node.js 版本检查通过: $NODE_VERSION"

    touch "$BASHRC" 2>/dev/null

    log "设置 NPM 镜像"
    npm config set registry https://registry.npmmirror.com
    if [ $? -ne 0 ]; then
        log "NPM 镜像设置失败"
        echo -e "${RED}错误：NPM 镜像设置失败${NC}"
        exit 1
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

    # 在安装前创建必要的目录（Termux 兼容性处理）
    log "创建 Termux 兼容性目录"
    mkdir -p "$LOG_DIR" "$HOME/tmp"
    if [ $? -ne 0 ]; then
        log "目录创建失败"
        echo -e "${RED}错误：目录创建失败${NC}"
        exit 1
    fi

    # 检查并安装/更新 Openclaw
    INSTALLED_VERSION=""
    LATEST_VERSION=""
    NEED_UPDATE=0

    log "检查 Openclaw 安装状态"
    if [ -f "$NPM_BIN/openclaw" ]; then
        log "Openclaw 已安装，检查版本"
        echo -e "${BLUE}检查 Openclaw 版本...${NC}"
        INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
        if [ -z "$INSTALLED_VERSION" ]; then
            log "版本提取失败，尝试备用方法"
            INSTALLED_VERSION=$(npm view openclaw version 2>/dev/null || echo "unknown")
        fi
        echo -e "${BLUE}当前版本: $INSTALLED_VERSION${NC}"

        # 获取最新版本
        log "获取最新版本信息"
        echo -e "${BLUE}正在从 npm 获取最新版本信息...${NC}"
        LATEST_VERSION=$(npm view openclaw version 2>/dev/null || echo "")

        if [ -z "$LATEST_VERSION" ]; then
            log "无法获取最新版本信息"
            echo -e "${YELLOW}⚠️  无法获取最新版本信息（可能是网络问题），保持当前版本${NC}"
        else
            echo -e "${BLUE}最新版本: $LATEST_VERSION${NC}"

            # 简单版本比较
            if [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
                log "发现新版本: $LATEST_VERSION (当前: $INSTALLED_VERSION)"
                echo -e "${YELLOW}🔔 发现新版本: $LATEST_VERSION (当前: $INSTALLED_VERSION)${NC}"

                if [ $FORCE_UPDATE -eq 1 ]; then
                    log "强制更新模式，直接更新"
                    echo -e "${YELLOW}正在更新 Openclaw...${NC}"
                    run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw --ignore-scripts
                    if [ $? -ne 0 ]; then
                        log "Openclaw 更新失败"
                        echo -e "${RED}错误：Openclaw 更新失败${NC}"
                        exit 1
                    fi
                    log "Openclaw 更新完成"
                    echo -e "${GREEN}✅ Openclaw 已更新到 $LATEST_VERSION${NC}"
                else
                    read -p "是否更新到新版本? (y/n) [默认: y]: " UPDATE_CHOICE
                    UPDATE_CHOICE=${UPDATE_CHOICE:-y}

                    if [ "$UPDATE_CHOICE" = "y" ] || [ "$UPDATE_CHOICE" = "Y" ]; then
                        log "开始更新 Openclaw"
                        echo -e "${YELLOW}正在更新 Openclaw...${NC}"
                        run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw --ignore-scripts
                        if [ $? -ne 0 ]; then
                            log "Openclaw 更新失败"
                            echo -e "${RED}错误：Openclaw 更新失败${NC}"
                            exit 1
                        fi
                        log "Openclaw 更新完成"
                        echo -e "${GREEN}✅ Openclaw 已更新到 $LATEST_VERSION${NC}"
                    else
                        log "用户选择跳过更新"
                        echo -e "${YELLOW}跳过更新，使用当前版本${NC}"
                    fi
                fi
            else
                log "版本已是最新"
                echo -e "${GREEN}✅ Openclaw 已是最新版本 $INSTALLED_VERSION${NC}"
            fi
        fi
    else
        log "开始安装 Openclaw"
        echo -e "${YELLOW}正在安装 Openclaw...${NC}"
        # 安装 Openclaw (使用 --ignore-scripts 跳过原生模块编译)
        # 设置环境变量跳过 node-llama-cpp 下载/编译（Termux 环境不支持）
        run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw --ignore-scripts
        if [ $? -ne 0 ]; then
            log "Openclaw 安装失败"
            echo -e "${RED}错误：Openclaw 安装失败${NC}"
            exit 1
        fi
        log "Openclaw 安装完成"
        INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
        if [ -z "$INSTALLED_VERSION" ]; then
            INSTALLED_VERSION=$(npm view openclaw version 2>/dev/null || echo "unknown")
        fi
        echo -e "${GREEN}✅ Openclaw 已安装 (版本: $INSTALLED_VERSION)${NC}"
    fi

    BASE_DIR="$NPM_GLOBAL/lib/node_modules/openclaw"
    
    # 应用 koffi stub (Termux 兼容性修复)
    apply_koffi_stub
}

apply_patches() {
    # Apply Android compatibility patches
    log "开始应用补丁"
    echo -e "${YELLOW}[3/6] 正在应用 Android 兼容性补丁...${NC}"

    # 修复所有包含 /tmp/openclaw 路径的文件
    log "搜索并修复所有硬编码的 /tmp/openclaw 路径"
    
    # 在 openclaw 目录中搜索所有包含 /tmp/openclaw 的文件
    cd "$BASE_DIR"
    FILES_WITH_TMP=$(grep -rl "/tmp/openclaw" dist/ 2>/dev/null || true)
    
    if [ -n "$FILES_WITH_TMP" ]; then
        log "找到需要修复的文件"
        for file in $FILES_WITH_TMP; do
            log "修复文件: $file"
            node -e "const fs = require('fs'); const file = '$BASE_DIR/$file'; let c = fs.readFileSync(file, 'utf8'); c = c.replace(/\/tmp\/openclaw/g, process.env.HOME + '/openclaw-logs'); fs.writeFileSync(file, c);"
        done
        log "所有文件修复完成"
    else
        log "未找到需要修复的文件"
    fi
    
    # 验证补丁是否生效
    REMAINING=$(grep -r "/tmp/openclaw" dist/ 2>/dev/null || true)
    if [ -n "$REMAINING" ]; then
        log "补丁验证失败，仍有文件包含 /tmp/openclaw"
        echo -e "${RED}警告：部分文件仍包含 /tmp/openclaw 路径${NC}"
        echo -e "${YELLOW}受影响的文件：${NC}"
        echo "$REMAINING"
    else
        log "补丁验证成功，所有路径已替换"
        echo -e "${GREEN}✓ 所有 /tmp/openclaw 路径已替换为 $HOME/openclaw-logs${NC}"
    fi

    # 修复硬编码的 /bin/npm 路径（Termux 下 npm 位于 $PREFIX/bin/npm）
    log "搜索并修复硬编码的 /bin/npm 路径"
    REAL_NPM=$(which npm 2>/dev/null || echo "")
    if [ -n "$REAL_NPM" ] && [ "$REAL_NPM" != "/bin/npm" ]; then
        FILES_WITH_NPM=$(grep -rl '"/bin/npm"' dist/ 2>/dev/null || true)
        if [ -z "$FILES_WITH_NPM" ]; then
            FILES_WITH_NPM=$(grep -rl "'/bin/npm'" dist/ 2>/dev/null || true)
        fi
        if [ -z "$FILES_WITH_NPM" ]; then
            FILES_WITH_NPM=$(grep -rl '/bin/npm' dist/ 2>/dev/null || true)
        fi
        
        if [ -n "$FILES_WITH_NPM" ]; then
            log "找到包含 /bin/npm 的文件，替换为 $REAL_NPM"
            for file in $FILES_WITH_NPM; do
                log "修复文件: $file"
                sed -i "s|/bin/npm|${REAL_NPM}|g" "$BASE_DIR/$file"
            done
            echo -e "${GREEN}✓ /bin/npm 路径已替换为 $REAL_NPM${NC}"
        else
            log "未找到包含 /bin/npm 的文件"
        fi
    else
        log "npm 路径无需修复"
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
    # Configure aliases and optional autostart
    log "配置环境变量和别名"
    # 备份原 ~/.bashrc 文件
    run_cmd cp "$BASHRC" "$BASHRC.backup"
    # 清理旧配置块（兼容旧版大小写不一致的标记）
    run_cmd sed -i '/# --- [Oo]pen[Cc]law Start ---/,/# --- [Oo]pen[Cc]law End ---/d' "$BASHRC"
    if [ $? -ne 0 ]; then
        log "bashrc 修改失败"
        echo -e "${RED}错误：bashrc 修改失败${NC}"
        exit 1
    fi

    # 构建 autostart 部分（仅当用户选择自启动时才包含 sshd/wake-lock）
    AUTOSTART_BLOCK=""
    if [ "$AUTO_START" == "y" ]; then
        log "配置自启动"
        AUTOSTART_BLOCK="sshd 2>/dev/null
termux-wake-lock 2>/dev/null"
    else
        log "跳过自启动（仅写入别名和环境变量）"
    fi

    # 写入配置块（aliases 始终写入，$NPM_BIN 在写入时展开为实际路径）
    cat >> "$BASHRC" <<EOT
# --- OpenClaw Start ---
# WARNING: This section contains your access token - keep ~/.bashrc secure
export TERMUX_VERSION=1
export TMPDIR=\$HOME/tmp
export OPENCLAW_GATEWAY_TOKEN=$TOKEN
export PATH=$NPM_BIN:\$PATH
${AUTOSTART_BLOCK}
alias ocr="pkill -9 -f 'openclaw' 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null; sleep 1; tmux new -d -s openclaw; sleep 1; tmux send-keys -t openclaw \"export PATH=$NPM_BIN:\$PATH TMPDIR=\$HOME/tmp; export OPENCLAW_GATEWAY_TOKEN=$TOKEN; openclaw gateway --bind loopback --port $PORT --token \\\$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured\" C-m"
alias oclog='tmux attach -t openclaw'
alias ockill='pkill -9 -f "openclaw" 2>/dev/null; tmux kill-session -t openclaw 2>/dev/null'
# --- OpenClaw End ---
EOT

    source "$BASHRC"
    if [ $? -ne 0 ]; then
        log "bashrc 加载警告"
        echo -e "${YELLOW}警告：bashrc 加载失败，可能影响别名${NC}"
    fi
    log "别名和环境变量配置完成"
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

    # 检查是否有实例在运行
    RUNNING_PROCESS=$(pgrep -f "openclaw gateway" 2>/dev/null || true)
    HAS_TMUX_SESSION=$(tmux has-session -t openclaw 2>/dev/null && echo "yes" || echo "no")

    if [ -n "$RUNNING_PROCESS" ] || [ "$HAS_TMUX_SESSION" = "yes" ]; then
        log "发现已有 Openclaw 实例在运行"
        echo -e "${YELLOW}⚠️  检测到 Openclaw 实例已在运行${NC}"
        echo -e "${BLUE}运行中的进程: $RUNNING_PROCESS${NC}"
        read -p "是否停止旧实例并启动新实例? (y/n) [默认: y]: " RESTART_CHOICE
        RESTART_CHOICE=${RESTART_CHOICE:-y}

        if [ "$RESTART_CHOICE" = "y" ] || [ "$RESTART_CHOICE" = "Y" ]; then
            log "停止旧实例"
            echo -e "${YELLOW}正在停止旧实例...${NC}"
            # 只停止 openclaw 相关进程，不杀死所有 node 进程
            pkill -9 -f "openclaw" 2>/dev/null || true
            tmux kill-session -t openclaw 2>/dev/null || true
            sleep 1
        else
            log "用户选择不重启"
            echo -e "${GREEN}跳过启动，保持当前实例运行${NC}"
            return 0
        fi
    fi

    # 2. 确保目录存在
    mkdir -p "$HOME/tmp"
    export TMPDIR="$HOME/tmp"

    # 3. 创建会话并捕获可能的错误
    # 这里我们先启动一个 shell，再在 shell 里执行命令，方便观察
    tmux new -d -s openclaw
    sleep 1
    
    # 将输出重定向到一个临时文件，如果 tmux 崩了也能看到报错
    tmux send-keys -t openclaw "export PATH=$NPM_BIN:\$PATH TMPDIR=$HOME/tmp; export OPENCLAW_GATEWAY_TOKEN=$TOKEN; openclaw gateway --bind loopback --port $PORT --token \\\$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured 2>&1 | tee $LOG_DIR/runtime.log" C-m
    
    log "服务指令已发送"
    echo -e "${GREEN}[6/6] 部署指令发送完毕${NC}"
    
    # 4. 实时验证
    sleep 2
    if tmux has-session -t openclaw 2>/dev/null; then
        echo -e "${GREEN}✅ tmux 会话已建立！${NC}"
        echo -e "执行 openclaw onboard 命令开始配置"
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
    run_cmd sed -i '/# --- [Oo]pen[Cc]law Start ---/,/# --- [Oo]pen[Cc]law End ---/d' "$BASHRC"
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
CYAN='\033[0;36m'
BOLD='\033[1m'
WHITE_ON_BLUE='\033[44;37;1m'
NC='\033[0m'

# 检查终端是否支持颜色
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    : # 支持，保持颜色
else
    GREEN=''
    BLUE=''
    YELLOW=''
    RED=''
    CYAN=''
    BOLD=''
    WHITE_ON_BLUE=''
    NC=''
fi

# 定义常用路径变量
BASHRC="$HOME/.bashrc"
NPM_GLOBAL="$HOME/.npm-global"
NPM_BIN="$NPM_GLOBAL/bin"
LOG_DIR="$HOME/openclaw-logs"
LOG_FILE="$LOG_DIR/install.log"

# 创建日志目录（防止日志函数在目录不存在时报错）
mkdir -p "$LOG_DIR" 2>/dev/null || true

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
read -p "请输入 Gateway 端口号 [默认: 18789]: " INPUT_PORT
if [ -z "$INPUT_PORT" ]; then
    echo -e "${GREEN}✓ 使用默认端口: 18789${NC}"
    PORT=18789
else
    # 验证输入的端口号是否为数字
    if ! [[ "$INPUT_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误：端口号必须是数字，使用默认值 18789${NC}"
        PORT=18789
    else
        PORT=$INPUT_PORT
        echo -e "${GREEN}✓ 使用端口: $PORT${NC}"
    fi
fi

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

echo ""
echo -e "${GREEN}=========================================="
echo -e "   ✅ 部署完成！"
echo -e "==========================================${NC}"
echo ""
echo -e "Token: ${YELLOW}$TOKEN${NC}"
echo ""
echo -e "${BLUE}┌─────────────────────────────────────┐${NC}"
echo -e "${BLUE}│${NC}  常用命令                           ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ─────────────────────────────────  ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ${CYAN}oclog${NC}    - 查看运行状态            ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ${CYAN}ockill${NC}   - 停止服务                ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ${CYAN}ocr${NC}      - 重启服务                ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────┘${NC}"
echo ""

# dry-run 模式跳过配置引导
if [ $DRY_RUN -eq 1 ]; then
    echo -e "${YELLOW}模拟运行完成，未执行实际安装${NC}"
    log "模拟运行完成"
    exit 0
fi

# 更新模式跳过配置引导
if [ $FORCE_UPDATE -eq 1 ]; then
    echo -e "${GREEN}更新完成！${NC}"
    log "更新完成"
    exit 0
fi

# 检查服务是否正常启动
if ! tmux has-session -t openclaw 2>/dev/null; then
    echo -e "${RED}服务启动失败，请检查日志后手动执行 openclaw onboard${NC}"
    log "服务启动失败"
    exit 1
fi

# 显示最终信息的函数
show_final_info() {
    local CONFIGURED=$1
    local SHOW_IGNORE_HINT=$2
    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  常用命令                           ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ─────────────────────────────────  ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}oclog${NC}    - 查看运行状态            ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}ockill${NC}   - 停止服务                ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}ocr${NC}      - 重启服务                ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────┘${NC}"
    echo ""
    if [ "$CONFIGURED" = "true" ]; then
        echo -e "${GREEN}✅ 配置完成！${NC}"
        echo ""
        echo -e "${CYAN}👉 下一步：手机浏览器访问${NC}"
        echo -e "${WHITE_ON_BLUE} http://localhost:$PORT/?token=$TOKEN ${NC}"
    else
        echo -e "${YELLOW}后续请手动执行 openclaw onboard 继续配置${NC}"
        if [ "$SHOW_IGNORE_HINT" = "true" ]; then
            echo -e "${YELLOW}提示：若显示 'Gateway service install not supported on android' 错误，可忽略${NC}"
        fi
    fi
}

# 配置引导
echo -e "${CYAN}按 Enter 键开始配置 OpenClaw...${NC}"
read -r

echo ""
echo -e "${YELLOW}即将执行 openclaw onboard 命令开始配置 OpenClaw${NC}"
echo -e "${YELLOW}请准备好大模型 API Key（支持 OpenAI、Anthropic、DeepSeek 等）${NC}"
echo ""
read -p "是否继续？[Y/n]: " CONTINUE_ONBOARD
CONTINUE_ONBOARD=${CONTINUE_ONBOARD:-y}

if [[ "$CONTINUE_ONBOARD" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${GREEN}正在启动配置向导...${NC}"
    echo -e "${YELLOW}提示：配置完成后若显示 'Gateway service install not supported on android' 错误，可忽略${NC}"
    echo ""
    # 捕获 Ctrl+C
    trap 'echo -e "\n${YELLOW}已取消配置${NC}"; show_final_info "false" "true"; log "用户取消配置"' INT
    openclaw onboard
    trap - INT

    # 检查配置文件是否存在且有效
    if [ -f "$HOME/.openclaw/openclaw.json" ] && node -e "JSON.parse(require('fs').readFileSync('$HOME/.openclaw/openclaw.json'))" 2>/dev/null; then
        show_final_info "true" "false"
    else
        show_final_info "false" "true"
    fi
    log "脚本执行完成"
else
    show_final_info "false" "true"
    log "用户跳过配置"
fi

