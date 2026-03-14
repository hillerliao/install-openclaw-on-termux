#!/bin/bash
# ==========================================
# Openclaw Termux Deployment Script v2
# Install/update/uninstall flows are integrated in staged form
# ==========================================

APP_NAME="OpenClaw Termux 部署工具"
APP_VERSION="2.1.0-wip"

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_NAME="$(basename "$SCRIPT_PATH")"
SCRIPT_SOURCED=0
if [[ "$SCRIPT_PATH" != "$0" ]]; then
    SCRIPT_SOURCED=1
fi

VERBOSE=0
DRY_RUN=0
UNINSTALL=0
FORCE_UPDATE=0
SHOW_HELP=0
NON_INTERACTIVE=0
LIST_VERSIONS=0
OPENCLAW_SPECIFIC_VERSION=""

DEFAULT_PORT=18789
DEFAULT_AUTO_START="y"
MIN_NODE_MAJOR=22
UPDATE_FLAG="$HOME/.pkg_last_update"
TMP_DIR="$HOME/tmp"
NPM_REGISTRY_URL="https://registry.npmmirror.com"
OPENCLAW_PACKAGE="openclaw"
OPENCLAW_TARGET_VERSION="latest"

PORT=""
TOKEN=""
AUTO_START=""
DEPENDENCY_INSTALL_PENDING=0
OPENCLAW_INSTALL_PENDING=0

BASHRC="$HOME/.bashrc"
NPM_GLOBAL="$HOME/.npm-global"
NPM_BIN="$NPM_GLOBAL/bin"
OPENCLAW_BASE_DIR="$NPM_GLOBAL/lib/node_modules/$OPENCLAW_PACKAGE"
OPENCLAW_BIN="$NPM_BIN/openclaw"
LOG_DIR="$HOME/openclaw-logs"
LOG_FILE="$LOG_DIR/install-v2.log"
OPENCLAW_ENV_FILE="$HOME/.config/openclaw/env.sh"
OPENCLAW_SHELL_BLOCK_START="# --- OpenClaw v2 Start ---"
OPENCLAW_SHELL_BLOCK_END="# --- OpenClaw v2 End ---"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

init_colors() {
    if ! [ -t 1 ] || [ "$(tput colors 2>/dev/null || echo 0)" -lt 8 ]; then
        GREEN=''; BLUE=''; YELLOW=''; RED=''; CYAN=''; BOLD=''; NC=''
    fi
}

ensure_log_dir() {
    mkdir -p "$LOG_DIR" 2>/dev/null || true
}

log() {
    ensure_log_dir
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

info() { echo -e "${BLUE}$*${NC}"; }
success() { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}$*${NC}"; }
error() { echo -e "${RED}$*${NC}" >&2; }

die() {
    local message="$1"
    local code="${2:-1}"
    log "ERROR: $message"
    error "错误：$message"
    return "$code"
}

run_cmd() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "[VERBOSE] $*"
    fi
    log "RUN: $*"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] $*"
        return 0
    fi
    "$@"
}

print_banner() {
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${BOLD}   🦞 ${APP_NAME} v2${NC}"
    echo -e "${BLUE}==========================================${NC}"
}

show_help() {
    cat <<EOF
用法:
  source ${SCRIPT_NAME} [选项]
  bash ${SCRIPT_NAME} [选项]

说明:
  当前文件已接入安装/更新/卸载主流程。
  卸载会清理 v2 受管 shell 配置、env.sh、OpenClaw 全局包、运行日志与 openclaw.json（删除前会先备份）。

选项:
  --help, -h           显示帮助
  --verbose, -v       启用详细输出
  --dry-run, -d       模拟运行
  --uninstall, -u     卸载 OpenClaw 与 v2 受管配置
  --update, -U        强制更新已安装的 OpenClaw
  --version, -V <ver> 指定 OpenClaw 版本（如 1.0.0）
  --list-versions     列出所有可用的 OpenClaw 版本
  --yes               非交互模式，使用默认值
  --port <port>       指定 Gateway 端口
  --token <token>     指定 Gateway Token
  --auto-start        启用自启动
  --no-auto-start     禁用自启动
EOF
}

normalize_yes_no() {
    case "$1" in
        y|Y|yes|YES|Yes) echo "y" ;;
        n|N|no|NO|No) echo "n" ;;
        *) echo "" ;;
    esac
}

generate_token() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import secrets; print(secrets.token_urlsafe(24))"
        return 0
    fi
    if command -v python >/dev/null 2>&1; then
        python -c "import secrets; print(secrets.token_urlsafe(24))"
        return 0
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 18
        return 0
    fi
    printf 'token%s%s' "$(date +%s)" "$$"
}

is_valid_port() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 1 ] && [ "$1" -le 65535 ]
}

mask_token() {
    local value="$1"
    local length=${#value}
    if [ "$length" -le 8 ]; then
        printf '%s' "$value"
        return 0
    fi
    printf '%s...%s' "${value:0:4}" "${value:length-4:4}"
}

is_termux_environment() {
    [ -n "${PREFIX:-}" ] && [ -x "${PREFIX}/bin/pkg" ]
}

require_termux_runtime() {
    if is_termux_environment; then
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "当前不是 Termux 环境：依赖安装步骤将以 dry-run 方式跳过真实执行"
        return 0
    fi

    die "当前运行环境不是 Termux，无法执行依赖安装和环境配置"
    return $?
}

path_contains() {
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
        *) return 1 ;;
    esac
}

append_path_for_current_shell() {
    if ! path_contains "$NPM_BIN"; then
        export PATH="$NPM_BIN:$PATH"
    fi
}

apply_runtime_env_for_current_shell() {
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] export PATH=$NPM_BIN:\$PATH"
        echo "[DRY-RUN] export TMPDIR=$TMP_DIR"
        return 0
    fi

    append_path_for_current_shell
    export TMPDIR="$TMP_DIR"
}

write_text_file() {
    local target_path="$1"
    local content="$2"

    log "WRITE: $target_path"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] write file: $target_path"
        return 0
    fi

    printf '%s\n' "$content" > "$target_path"
}

append_text_file() {
    local target_path="$1"
    local content="$2"

    log "APPEND: $target_path"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] append file: $target_path"
        return 0
    fi

    printf '\n%s\n' "$content" >> "$target_path"
}

ensure_parent_dir() {
    local target_path="$1"
    local parent_dir=""

    parent_dir="$(dirname "$target_path")"
    run_cmd mkdir -p "$parent_dir" || {
        die "无法创建目录：$parent_dir"
        return $?
    }
}

render_bash_export() {
    local var_name="$1"
    local var_value="${2-}"

    printf 'export %s=%q\n' "$var_name" "$var_value"
}

render_openclaw_env_content() {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'export TERMUX_VERSION=1'
    render_bash_export "TMPDIR" "$TMP_DIR"
    render_bash_export "OPENCLAW_PORT" "$PORT"
    render_bash_export "OPENCLAW_GATEWAY_TOKEN" "$TOKEN"
    render_bash_export "OPENCLAW_AUTO_START" "$AUTO_START"
    render_bash_export "OPENCLAW_LOG_DIR" "$LOG_DIR"
    render_bash_export "OPENCLAW_NPM_BIN" "$NPM_BIN"
    render_bash_export "OPENCLAW_BIN" "$OPENCLAW_BIN"
}

openclaw_gateway_process_pattern() {
    printf '%s' "$OPENCLAW_BASE_DIR/dist/entry.js gateway"
}

find_openclaw_gateway_processes() {
    local gateway_pattern=""
    gateway_pattern="$(openclaw_gateway_process_pattern)"

    if ! command -v pgrep >/dev/null 2>&1; then
        return 0
    fi

    pgrep -f "$gateway_pattern" 2>/dev/null || true
}

stop_openclaw_gateway_service() {
    local gateway_pattern=""
    local leftover_processes=""
    gateway_pattern="$(openclaw_gateway_process_pattern)"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[DRY-RUN] tmux kill-session -t openclaw"
        echo "[DRY-RUN] pkill -f $gateway_pattern"
        echo "[DRY-RUN] pkill -9 -f $gateway_pattern"
        return 0
    fi

    log "STOP: OpenClaw gateway service"
    if command -v tmux >/dev/null 2>&1; then
        tmux kill-session -t openclaw >/dev/null 2>&1 || true
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "$gateway_pattern" >/dev/null 2>&1 || true
        sleep 1
        leftover_processes="$(find_openclaw_gateway_processes)"
        if [ -n "$leftover_processes" ]; then
            pkill -9 -f "$gateway_pattern" >/dev/null 2>&1 || true
        fi
    fi
    sleep 1
}

build_gateway_tmux_command() {
    printf '%s' "if [ -f \"$OPENCLAW_ENV_FILE\" ]; then . \"$OPENCLAW_ENV_FILE\"; fi; export PATH=\"$NPM_BIN:\$PATH\" TMPDIR=\"$TMP_DIR\"; openclaw gateway --bind loopback --port \"\${OPENCLAW_PORT:-$PORT}\" --token \"\$OPENCLAW_GATEWAY_TOKEN\" --allow-unconfigured 2>&1 | tee \"$LOG_DIR/runtime.log\""
}

render_openclaw_runtime_functions() {
    local gateway_cmd=""
    gateway_cmd="$(build_gateway_tmux_command)"

    cat <<EOF
_openclaw_runtime_gateway_pattern() {
    printf '%s' '$OPENCLAW_BASE_DIR/dist/entry.js gateway'
}

_openclaw_runtime_stop_gateway_service() {
    local gateway_pattern=""
    gateway_pattern="\$(_openclaw_runtime_gateway_pattern)"

    if command -v tmux >/dev/null 2>&1; then
        tmux kill-session -t openclaw 2>/dev/null || true
    fi
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "$gateway_pattern" 2>/dev/null || true
        sleep 1
        if command -v pgrep >/dev/null 2>&1 && pgrep -f "$gateway_pattern" >/dev/null 2>&1; then
            pkill -9 -f "$gateway_pattern" 2>/dev/null || true
        fi
    fi
    sleep 1
}

ocr() {
    local gateway_cmd='$gateway_cmd'
    [ -f "$OPENCLAW_ENV_FILE" ] && . "$OPENCLAW_ENV_FILE"
    case ":\$PATH:" in
        *":$NPM_BIN:"*) ;;
        *) export PATH="$NPM_BIN:\$PATH" ;;
    esac
    export TMPDIR="\${TMPDIR:-$TMP_DIR}"
    _openclaw_runtime_stop_gateway_service
    tmux new-session -d -s openclaw "\$gateway_cmd" || return \$?
    sleep 2
    if tmux has-session -t openclaw 2>/dev/null; then
        echo "✅ OpenClaw 服务已启动"
        echo "浏览器访问: http://localhost:\${OPENCLAW_PORT:-$PORT}/?token=\$OPENCLAW_GATEWAY_TOKEN"
    else
        echo "❌ 服务启动失败，请检查 $LOG_DIR/runtime.log"
    fi
}

oclog() {
    if tmux has-session -t openclaw 2>/dev/null; then
        tmux attach -t openclaw
    else
        echo "⚠️  OpenClaw 服务未运行，请先执行 ocr"
    fi
}

ockill() {
    _openclaw_runtime_stop_gateway_service
    if tmux has-session -t openclaw 2>/dev/null || \
        (command -v pgrep >/dev/null 2>&1 && pgrep -f "\$(_openclaw_runtime_gateway_pattern)" >/dev/null 2>&1); then
        echo "❌ OpenClaw 服务仍在运行，请手动检查"
    else
        echo "✅ OpenClaw 服务已停止"
    fi
}
EOF
}

render_openclaw_shell_block() {
    local runtime_functions=""
    runtime_functions="$(render_openclaw_runtime_functions)"

    cat <<EOF
$OPENCLAW_SHELL_BLOCK_START
if [ -f "$OPENCLAW_ENV_FILE" ]; then
    . "$OPENCLAW_ENV_FILE"
fi
case ":\$PATH:" in
    *":$NPM_BIN:"*) ;;
    *) export PATH="$NPM_BIN:\$PATH" ;;
esac
if [ "\${OPENCLAW_AUTO_START:-n}" = "y" ]; then
    command -v sshd >/dev/null 2>&1 && sshd 2>/dev/null || true
    command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock 2>/dev/null || true
fi

$runtime_functions
$OPENCLAW_SHELL_BLOCK_END
EOF
}

remove_openclaw_shell_block() {
    [ -f "$BASHRC" ] || return 0

    if ! grep -Fq "$OPENCLAW_SHELL_BLOCK_START" "$BASHRC" 2>/dev/null; then
        return 0
    fi

    run_cmd sed -i '/^# --- OpenClaw v2 Start ---$/,/^# --- OpenClaw v2 End ---$/d' "$BASHRC" || {
        die "无法清理旧的 OpenClaw shell 配置块"
        return $?
    }
}

cleanup_current_shell_openclaw_runtime() {
    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过当前 shell 即时清理，仅展示将移除的运行时配置"
        return 0
    fi

    unset -f ocr oclog ockill _openclaw_runtime_gateway_pattern _openclaw_runtime_stop_gateway_service 2>/dev/null || true
    unset OPENCLAW_GATEWAY_TOKEN OPENCLAW_PORT OPENCLAW_AUTO_START OPENCLAW_LOG_DIR OPENCLAW_NPM_BIN OPENCLAW_BIN
    hash -r 2>/dev/null || true
}

confirm_with_default() {
    local prompt="$1"
    local default_choice="$2"
    local input_choice=""
    local normalized_choice=""

    if [ "$NON_INTERACTIVE" -eq 1 ] || ! [ -t 0 ]; then
        printf '%s' "$default_choice"
        return 0
    fi

    read -r -p "$prompt" input_choice || {
        printf '%s' "$default_choice"
        return 0
    }

    normalized_choice=$(normalize_yes_no "${input_choice:-$default_choice}")
    if [ -z "$normalized_choice" ]; then
        normalized_choice="$default_choice"
    fi
    printf '%s' "$normalized_choice"
}

get_node_major_version() {
    node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1
}

is_openclaw_installed() {
    [ -d "$OPENCLAW_BASE_DIR" ] || [ -f "$OPENCLAW_BIN" ]
}

get_openclaw_local_version() {
    local package_json="$OPENCLAW_BASE_DIR/package.json"

    if [ ! -f "$package_json" ]; then
        return 1
    fi

    grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$package_json" 2>/dev/null \
        | head -n 1 \
        | sed -E 's/.*"([^"]+)"/\1/'
}

get_openclaw_latest_version() {
    npm view "$OPENCLAW_PACKAGE" version 2>/dev/null || true
}

list_openclaw_versions() {
    info "获取 OpenClaw 可用版本列表..."
    local versions
    versions=$(npm view "$OPENCLAW_PACKAGE" versions --json 2>/dev/null)
    if [ -z "$versions" ]; then
        die "无法获取版本列表，请检查网络连接"
        return $?
    fi
    echo "$versions" | node -e "
const versions = JSON.parse(require('fs').readFileSync(0, 'utf8'));
versions.forEach((v, i) => {
    console.log('  ' + v);
});
"
    success "共 $(echo "$versions" | node -e 'console.log(JSON.parse(require(\"fs\").readFileSync(0, \"utf8\")).length)') 个版本"
}

install_openclaw_package() {
    log "安装/更新 OpenClaw 包"
    OPENCLAW_INSTALL_PENDING=1
    local install_version="$OPENCLAW_TARGET_VERSION"
    if [ -n "$OPENCLAW_SPECIFIC_VERSION" ]; then
        install_version="$OPENCLAW_SPECIFIC_VERSION"
    fi
    run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g "${OPENCLAW_PACKAGE}@${install_version}" --ignore-scripts || {
        die "OpenClaw 安装/更新失败"
        return $?
    }
    return 0
}

ensure_openclaw_dist_layout() {
    if [ "$DRY_RUN" -eq 1 ] && [ "$OPENCLAW_INSTALL_PENDING" -eq 1 ]; then
        warn "dry-run 下跳过 OpenClaw dist 目录校验"
        return 0
    fi

    if [ ! -d "$OPENCLAW_BASE_DIR" ]; then
        die "OpenClaw 安装目录不存在：$OPENCLAW_BASE_DIR"
        return $?
    fi

    if [ -f "$OPENCLAW_BASE_DIR/dist/entry.js" ]; then
        success "✅ OpenClaw 入口文件已就绪"
        return 0
    fi

    warn "检测到 dist/entry.js 缺失，尝试执行构建..."
    if [ -f "$OPENCLAW_BASE_DIR/tsconfig.json" ]; then
        run_cmd sh -c "cd '$OPENCLAW_BASE_DIR' && npx tsc --skipLibCheck" || true
    fi
    run_cmd sh -c "cd '$OPENCLAW_BASE_DIR' && npm run build" || true

    if [ ! -f "$OPENCLAW_BASE_DIR/dist/entry.js" ]; then
        die "OpenClaw 安装后缺少 dist/entry.js，后续阶段无法继续"
        return $?
    fi

    success "✅ OpenClaw dist 目录已就绪"
}

maybe_update_existing_openclaw() {
    local installed_version="$1"
    local latest_version="$2"
    local update_choice="n"

    # 如果用户指定了具体版本，直接安装
    if [ -n "$OPENCLAW_SPECIFIC_VERSION" ]; then
        info "指定版本: $OPENCLAW_SPECIFIC_VERSION"
        if [ -n "$installed_version" ] && [ "$installed_version" != "$OPENCLAW_SPECIFIC_VERSION" ]; then
            warn "⚠️  版本降级: ${installed_version} -> $OPENCLAW_SPECIFIC_VERSION"
        fi
        install_openclaw_package || return $?
        return 0
    fi

    if [ -z "$latest_version" ]; then
        warn "无法获取 OpenClaw 最新版本信息，保留当前版本：${installed_version:-unknown}"
        return 0
    fi

    info "当前版本: ${installed_version:-unknown}"
    info "最新版本: $latest_version"

    if [ -n "$installed_version" ] && [ "$installed_version" = "$latest_version" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
        success "✅ OpenClaw 已是最新版本 $installed_version"
        return 0
    fi

    # 检测版本降级情况
    if [ -n "$installed_version" ] && [ "$FORCE_UPDATE" -eq 0 ]; then
        warn "⚠️  检测到版本变更"
    fi

    if [ "$FORCE_UPDATE" -eq 1 ]; then
        warn "检测到 --update，直接执行更新"
        install_openclaw_package || return $?
        return 0
    fi

    update_choice=$(confirm_with_default "是否更新到新版本? (y/n) [默认: y]: " "y")
    if [ "$update_choice" != "y" ]; then
        warn "跳过更新，保留当前版本"
        return 0
    fi

    install_openclaw_package || return $?
}

replace_fixed_string_in_file() {
    local target_file="$1"
    local search_value="$2"
    local replace_value="$3"

    run_cmd env TARGET_FILE="$target_file" SEARCH_VALUE="$search_value" REPLACE_VALUE="$replace_value" \
        node -e "const fs = require('fs'); const file = process.env.TARGET_FILE; let c = fs.readFileSync(file, 'utf8'); c = c.split(process.env.SEARCH_VALUE).join(process.env.REPLACE_VALUE); fs.writeFileSync(file, c);" || {
        die "文件替换失败：$target_file"
        return $?
    }
}

patch_tmp_openclaw_paths() {
    local files_with_tmp=""
    local remaining=""
    local file=""

    [ -d "$OPENCLAW_BASE_DIR/dist" ] || return 0

    files_with_tmp=$(grep -rl "/tmp/openclaw" "$OPENCLAW_BASE_DIR/dist" 2>/dev/null || true)
    if [ -z "$files_with_tmp" ]; then
        log "未找到需要修复的 /tmp/openclaw 路径"
        return 0
    fi

    warn "检测到硬编码 /tmp/openclaw，开始替换为 $LOG_DIR"
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        log "修复文件: $file"
        replace_fixed_string_in_file "$file" "/tmp/openclaw" "$LOG_DIR" || return $?
    done <<< "$files_with_tmp"

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过 /tmp/openclaw 替换结果校验"
        return 0
    fi

    remaining=$(grep -r "/tmp/openclaw" "$OPENCLAW_BASE_DIR/dist" 2>/dev/null || true)
    if [ -n "$remaining" ]; then
        warn "仍有文件包含 /tmp/openclaw 路径"
        echo "$remaining"
        return 0
    fi

    success "✅ 所有 /tmp/openclaw 路径已替换为 $LOG_DIR"
}

patch_hardcoded_npm_path() {
    local real_npm=""
    local files_with_npm=""
    local file=""

    [ -d "$OPENCLAW_BASE_DIR/dist" ] || return 0

    real_npm=$(command -v npm 2>/dev/null || true)
    if [ -z "$real_npm" ] || [ "$real_npm" = "/bin/npm" ]; then
        log "npm 路径无需修复"
        return 0
    fi

    files_with_npm=$(grep -rl '/bin/npm' "$OPENCLAW_BASE_DIR/dist" 2>/dev/null || true)
    if [ -z "$files_with_npm" ]; then
        log "未找到硬编码 /bin/npm 路径"
        return 0
    fi

    warn "检测到硬编码 /bin/npm，开始替换为 $real_npm"
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        log "修复文件: $file"
        run_cmd sed -i "s|/bin/npm|${real_npm}|g" "$file" || {
            die "/bin/npm 路径替换失败：$file"
            return $?
        }
    done <<< "$files_with_npm"

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过 /bin/npm 替换结果校验"
        return 0
    fi

    success "✅ /bin/npm 路径已替换为 $real_npm"
}

apply_clipboard_stub() {
    local clip_file="$OPENCLAW_BASE_DIR/node_modules/@mariozechner/clipboard/index.js"
    local clip_stub='module.exports = { availableFormats:()=>[], getText:()=>"", setText:()=>false, hasText:()=>false, getImageBinary:()=>null, getImageBase64:()=>null, setImageBinary:()=>false, setImageBase64:()=>false, hasImage:()=>false, getHtml:()=>"", setHtml:()=>false, hasHtml:()=>false, getRtf:()=>"", setRtf:()=>false, hasRtf:()=>false, clear:()=>{}, watch:()=>({stop:()=>{}}), callThreadsafeFunction:()=>{} };'

    if [ ! -f "$clip_file" ]; then
        log "clipboard 模块文件不存在，跳过 stub"
        return 0
    fi

    warn "正在应用 clipboard stub..."
    write_text_file "$clip_file" "$clip_stub" || {
        die "clipboard stub 写入失败"
        return $?
    }

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过 clipboard stub 校验"
        return 0
    fi

    if ! grep -q "availableFormats" "$clip_file"; then
        die "clipboard stub 校验失败"
        return $?
    fi

    success "✅ clipboard stub 已应用"
}

apply_koffi_stub() {
    local koffi_dir="$OPENCLAW_BASE_DIR/node_modules/koffi"
    local koffi_file="$koffi_dir/index.js"
    local koffi_stub=""

    if [ ! -d "$koffi_dir" ]; then
        log "koffi 目录不存在，跳过 stub"
        return 0
    fi

    koffi_stub=$(cat <<'EOF'
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
)

    warn "正在应用 koffi stub..."
    write_text_file "$koffi_file" "$koffi_stub" || {
        die "koffi stub 写入失败"
        return $?
    }

    success "✅ koffi stub 已应用"
}

create_openclaw_wrapper() {
    local termux_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local shell_path="$termux_prefix/bin/sh"
    local entry_js="$OPENCLAW_BASE_DIR/dist/entry.js"
    local wrapper_content=""

    if [ ! -f "$entry_js" ]; then
        die "OpenClaw 入口文件不存在，无法创建包装脚本：$entry_js"
        return $?
    fi

    ensure_parent_dir "$OPENCLAW_BIN" || return $?
    if [ ! -x "$shell_path" ]; then
        warn "Termux shell 路径不存在，回退使用 /bin/sh：$shell_path"
        shell_path="/bin/sh"
    fi

    log "创建 openclaw 包装脚本以修复 ESM bin 路径解析"
    wrapper_content=$(cat <<EOF
#!$shell_path
exec node "$entry_js" "\$@"
EOF
)

    write_text_file "$OPENCLAW_BIN" "$wrapper_content" || {
        die "openclaw 包装脚本写入失败：$OPENCLAW_BIN"
        return $?
    }
    run_cmd chmod +x "$OPENCLAW_BIN" || {
        die "openclaw 包装脚本授权失败：$OPENCLAW_BIN"
        return $?
    }

    success "✅ openclaw 包装脚本已创建"
}

fix_openclaw_shebang() {
    local termux_prefix="${PREFIX:-/data/data/com.termux/files/usr}"
    local first_line=""

    if [ ! -f "$OPENCLAW_BIN" ]; then
        log "openclaw 可执行文件不存在，跳过 shebang 修复"
        return 0
    fi

    if [ -x "/usr/bin/env" ]; then
        log "/usr/bin/env 可用，无需修复 shebang"
        return 0
    fi

    first_line=$(head -n 1 "$OPENCLAW_BIN" 2>/dev/null || true)
    case "$first_line" in
        '#!/usr/bin/env'*) ;;
        *)
            log "openclaw shebang 无需修复"
            return 0
            ;;
    esac

    if [ ! -x "$termux_prefix/bin/env" ]; then
        warn "Termux env 路径不存在，跳过 shebang 修复：$termux_prefix/bin/env"
        return 0
    fi

    run_cmd sed -i "1s|#!/usr/bin/env|#!${termux_prefix}/bin/env|" "$OPENCLAW_BIN" || {
        die "openclaw shebang 修复失败"
        return $?
    }

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过 shebang 修复结果校验"
        return 0
    fi

    success "✅ openclaw shebang 已修复为 Termux 兼容路径"
}

check_dependency_available() {
    local dep="$1"
    case "$dep" in
        nodejs-lts) command -v node >/dev/null 2>&1 ;;
        git) command -v git >/dev/null 2>&1 ;;
        openssh) command -v ssh >/dev/null 2>&1 ;;
        tmux) command -v tmux >/dev/null 2>&1 ;;
        termux-api) command -v termux-wake-lock >/dev/null 2>&1 ;;
        termux-tools) command -v pkg >/dev/null 2>&1 ;;
        cmake) command -v cmake >/dev/null 2>&1 ;;
        python) command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 ;;
        golang) command -v go >/dev/null 2>&1 ;;
        which) command -v which >/dev/null 2>&1 ;;
        clang) command -v clang >/dev/null 2>&1 ;;
        ninja) command -v ninja >/dev/null 2>&1 ;;
        pkg-config) command -v pkg-config >/dev/null 2>&1 ;;
        build-essential) command -v make >/dev/null 2>&1 ;;
        *) command -v "$dep" >/dev/null 2>&1 ;;
    esac
}

maybe_refresh_pkg_index() {
    local should_update=0
    local last_update_ts=0
    local now_ts

    now_ts=$(date +%s)
    if [ ! -f "$UPDATE_FLAG" ]; then
        should_update=1
    else
        last_update_ts=$(stat -c %Y "$UPDATE_FLAG" 2>/dev/null || echo 0)
        if [ $((now_ts - last_update_ts)) -gt 86400 ]; then
            should_update=1
        fi
    fi

    if [ "$should_update" -eq 0 ]; then
        success "✅ 包列表更新缓存仍有效，跳过 pkg update"
        return 0
    fi

    warn "更新包列表..."
    run_cmd pkg update -y || {
        die "pkg update 失败"
        return $?
    }
    run_cmd touch "$UPDATE_FLAG" || {
        die "无法写入更新标记文件：$UPDATE_FLAG"
        return $?
    }
}

maybe_install_missing_dependencies() {
    local deps=("nodejs-lts" "git" "openssh" "tmux" "termux-api" "termux-tools" "cmake" "python" "golang" "which" "clang" "ninja" "pkg-config" "build-essential")
    local missing_deps=()
    local dep

    for dep in "${deps[@]}"; do
        if ! check_dependency_available "$dep"; then
            missing_deps+=("$dep")
        fi
    done

    if [ "${#missing_deps[@]}" -eq 0 ]; then
        success "✅ 基础依赖已就绪"
        return 0
    fi

    DEPENDENCY_INSTALL_PENDING=1
    warn "缺失依赖：${missing_deps[*]}"
    run_cmd pkg upgrade -y || {
        die "pkg upgrade 失败"
        return $?
    }
    run_cmd pkg install "${missing_deps[@]}" -y || {
        die "依赖安装失败：${missing_deps[*]}"
        return $?
    }
    success "✅ 缺失依赖安装完成"
}

check_node_version() {
    local node_major=""
    local downgrade_choice="n"
    local continue_choice="n"

    if ! command -v node >/dev/null 2>&1; then
        die "未检测到 node，可执行文件缺失"
        return $?
    fi
    if ! command -v npm >/dev/null 2>&1; then
        die "未检测到 npm，可执行文件缺失"
        return $?
    fi

    info "Node.js 版本: $(node -v 2>/dev/null || echo '未知')"
    info "NPM 版本: $(npm -v 2>/dev/null || echo '未知')"

    node_major=$(get_node_major_version)
    if [ -z "$node_major" ] || [ "$node_major" -lt "$MIN_NODE_MAJOR" ]; then
        die "Node.js 版本必须 >= ${MIN_NODE_MAJOR}，当前版本：$(node -v 2>/dev/null || echo '未知')"
        return $?
    fi

    if [ "$node_major" -eq 25 ]; then
        warn "⚠️ 检测到 Node.js 25（非 LTS），可能存在原生模块兼容性问题"
        if [ "$NON_INTERACTIVE" -eq 1 ]; then
            warn "非交互模式下不会自动降级 Node.js，请确认当前版本兼容"
            return 0
        fi

        downgrade_choice=$(confirm_with_default "是否降级到 Node.js 24 LTS? (y/n) [默认: y]: " "y")
        if [ "$downgrade_choice" = "y" ]; then
            run_cmd pkg uninstall nodejs -y || {
                die "Node.js 卸载失败"
                return $?
            }
            run_cmd pkg install nodejs-lts -y || {
                die "Node.js LTS 安装失败"
                return $?
            }
            if [ "$DRY_RUN" -eq 1 ]; then
                success "✅ 已模拟切换到 Node.js 24 LTS"
                return 0
            fi
            success "✅ Node.js 已切换为 $(node -v 2>/dev/null || echo '未知')"
            return 0
        fi

        continue_choice=$(confirm_with_default "继续使用 Node.js 25 安装? (y/n) [默认: n]: " "n")
        if [ "$continue_choice" != "y" ]; then
            die "已取消安装，请先切换到兼容的 Node.js LTS 版本" 2
            return $?
        fi
    fi

    success "✅ Node.js 版本检查通过"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v)
                VERBOSE=1
                ;;
            --dry-run|-d)
                DRY_RUN=1
                ;;
            --uninstall|-u)
                UNINSTALL=1
                ;;
            --update|-U)
                FORCE_UPDATE=1
                ;;
            --help|-h)
                SHOW_HELP=1
                ;;
            --yes)
                NON_INTERACTIVE=1
                ;;
            --port)
                shift
                [ $# -gt 0 ] || { die "--port 需要一个参数"; return $?; }
                PORT="$1"
                ;;
            --port=*)
                PORT="${1#*=}"
                ;;
            --token)
                shift
                [ $# -gt 0 ] || { die "--token 需要一个参数"; return $?; }
                TOKEN="$1"
                ;;
            --token=*)
                TOKEN="${1#*=}"
                ;;
            --auto-start)
                AUTO_START="y"
                ;;
            --no-auto-start)
                AUTO_START="n"
                ;;
            --version|-V)
                shift
                [ $# -gt 0 ] || { die "--version 需要一个参数"; return $?; }
                OPENCLAW_SPECIFIC_VERSION="$1"
                ;;
            --version=*|-V=*)
                OPENCLAW_SPECIFIC_VERSION="${1#*=}"
                ;;
            --list-versions)
                LIST_VERSIONS=1
                ;;
            *)
                die "未知选项: $1"
                return $?
                ;;
        esac
        shift
    done

    return 0
}

collect_port() {
    local input_port=""

    if [ -n "$PORT" ]; then
        if ! is_valid_port "$PORT"; then
            die "端口号无效：$PORT，允许范围 1-65535"
            return $?
        fi
        success "✓ 使用命令行指定端口: $PORT"
        return 0
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ] || ! [ -t 0 ]; then
        PORT="$DEFAULT_PORT"
        warn "非交互模式：使用默认端口 $PORT"
        return 0
    fi

    read -r -p "请输入 Gateway 端口号 [默认: ${DEFAULT_PORT}]: " input_port || {
        die "读取端口输入失败"
        return $?
    }

    if [ -z "$input_port" ]; then
        PORT="$DEFAULT_PORT"
        success "✓ 使用默认端口: $PORT"
        return 0
    fi

    if is_valid_port "$input_port"; then
        PORT="$input_port"
        success "✓ 使用端口: $PORT"
    else
        PORT="$DEFAULT_PORT"
        warn "输入端口无效，已回退到默认端口: $PORT"
    fi
}

prompt_for_custom_token() {
    local input_token=""

    read -r -p "请输入自定义 Token（留空自动生成）: " input_token || {
        die "读取 Token 输入失败"
        return $?
    }

    if [ -n "$input_token" ]; then
        TOKEN="$input_token"
        success "✓ 使用自定义 Token"
        return 0
    fi

    TOKEN="$(generate_token)"
    if [ -z "$TOKEN" ]; then
        die "自动生成 Token 失败"
        return $?
    fi
    success "✓ 已自动生成 Token: $(mask_token "$TOKEN")"
}

collect_token() {
    local existing_token="${OPENCLAW_GATEWAY_TOKEN:-}"
    local use_existing=""

    if [ -n "$TOKEN" ]; then
        success "✓ 使用命令行指定 Token: $(mask_token "$TOKEN")"
        return 0
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ] || ! [ -t 0 ]; then
        if [ -n "$existing_token" ]; then
            TOKEN="$existing_token"
            warn "非交互模式：使用现有环境变量 Token: $(mask_token "$TOKEN")"
            return 0
        fi
        TOKEN="$(generate_token)"
        if [ -z "$TOKEN" ]; then
            die "自动生成 Token 失败"
            return $?
        fi
        warn "非交互模式：已自动生成 Token: $(mask_token "$TOKEN")"
        return 0
    fi

    if [ -n "$existing_token" ]; then
        info "检测到现有 Token: $(mask_token "$existing_token")"
        read -r -p "是否使用现有 Token? (y/n) [默认: y]: " use_existing || {
            die "读取 Token 选择失败"
            return $?
        }
        use_existing=$(normalize_yes_no "${use_existing:-y}")
        if [ -z "$use_existing" ] || [ "$use_existing" = "y" ]; then
            TOKEN="$existing_token"
            success "✓ 使用现有 Token"
            return 0
        fi
    fi

    prompt_for_custom_token || return $?
}

collect_auto_start() {
    local input_choice=""

    if [ -n "$AUTO_START" ]; then
        AUTO_START=$(normalize_yes_no "$AUTO_START")
        if [ -z "$AUTO_START" ]; then
            die "自启动参数无效，请使用 --auto-start 或 --no-auto-start"
            return $?
        fi
        success "✓ 自启动设置: $AUTO_START"
        return 0
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ] || ! [ -t 0 ]; then
        AUTO_START="$DEFAULT_AUTO_START"
        warn "非交互模式：自启动默认设置为 $AUTO_START"
        return 0
    fi

    read -r -p "是否需要开启开机自启动? (y/n) [默认: ${DEFAULT_AUTO_START}]: " input_choice || {
        die "读取自启动输入失败"
        return $?
    }

    AUTO_START=$(normalize_yes_no "${input_choice:-$DEFAULT_AUTO_START}")
    if [ -z "$AUTO_START" ]; then
        AUTO_START="$DEFAULT_AUTO_START"
        warn "输入无效，已回退到默认自启动设置: $AUTO_START"
    else
        success "✓ 自启动设置: $AUTO_START"
    fi
}

collect_inputs() {
    collect_port || return $?
    collect_token || return $?
    collect_auto_start || return $?
    log "用户配置已收集: port=$PORT, auto_start=$AUTO_START, token_length=${#TOKEN}"
    return 0
}

show_phase2_summary() {
    local mode_label="interactive"
    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        mode_label="non-interactive"
    fi

    echo ""
    info "当前阶段：v2 主流程已接入输入采集、依赖准备、安装更新、补丁、shell 集成、服务启动与 onboard 引导"
    info "日志文件：$LOG_FILE"
    printf '  - 端口: %s\n' "$PORT"
    printf '  - Token: %s\n' "$(mask_token "$TOKEN")"
    printf '  - 自启动: %s\n' "$AUTO_START"
    printf '  - 模式: %s\n' "$mode_label"
    warn "接下来将继续执行安装、补丁、shell 集成、服务启动与 onboard 引导。"
}

check_deps() {
    warn "[1/5] 正在检查基础运行环境..."
    require_termux_runtime || return $?

    if ! is_termux_environment && [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过真实依赖检测与安装"
        return 0
    fi

    maybe_refresh_pkg_index || return $?
    maybe_install_missing_dependencies || return $?

    if [ "$DRY_RUN" -eq 1 ] && [ "$DEPENDENCY_INSTALL_PENDING" -eq 1 ]; then
        warn "dry-run 下检测到需要安装/升级依赖，跳过基于当前环境的 Node 版本强校验"
        return 0
    fi

    check_node_version || return $?
}

configure_npm() {
    warn "[2/5] 正在配置 NPM 与构建环境..."
    require_termux_runtime || return $?

    if ! is_termux_environment && [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过真实 NPM 环境配置"
        return 0
    fi

    run_cmd mkdir -p "$NPM_GLOBAL" "$TMP_DIR" "$HOME/.gyp" || {
        die "无法创建 NPM/临时/GYP 目录"
        return $?
    }

    run_cmd npm config set prefix "$NPM_GLOBAL" || {
        die "NPM prefix 设置失败"
        return $?
    }
    run_cmd npm config set registry "$NPM_REGISTRY_URL" || {
        die "NPM registry 设置失败"
        return $?
    }

    apply_runtime_env_for_current_shell

    run_cmd git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" || {
        warn "git ssh->https 映射配置失败（可稍后手动处理）"
    }
    run_cmd git config --global --add url."https://github.com/".insteadOf "git@github.com:" || {
        warn "git scp-style ssh->https 映射配置失败（可稍后手动处理）"
    }

    write_text_file "$HOME/.gyp/include.gypi" "{'variables':{'android_ndk_path':''}}" || {
        die "写入 GYP 配置失败"
        return $?
    }

    success "✅ NPM/TMPDIR/GYP 基础环境已配置到当前会话"
}

install_or_update_openclaw() {
    local installed_version=""
    local latest_version=""

    warn "[3/5] 正在安装/更新 OpenClaw..."
    require_termux_runtime || return $?

    if ! is_termux_environment && [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过真实 OpenClaw 安装/更新"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ] && [ "$DEPENDENCY_INSTALL_PENDING" -eq 1 ]; then
        warn "dry-run 下检测到依赖尚未真实安装，跳过 OpenClaw 包安装阶段"
        return 0
    fi

    installed_version=$(get_openclaw_local_version 2>/dev/null || true)
    latest_version=$(get_openclaw_latest_version)

    if is_openclaw_installed; then
        maybe_update_existing_openclaw "$installed_version" "$latest_version" || return $?
    else
        warn "未检测到已安装的 OpenClaw，准备首次安装"
        install_openclaw_package || return $?
    fi

    installed_version=$(get_openclaw_local_version 2>/dev/null || true)
    if [ -n "$installed_version" ]; then
        success "✅ OpenClaw 当前版本: $installed_version"
    elif [ "$DRY_RUN" -eq 1 ] && [ "$OPENCLAW_INSTALL_PENDING" -eq 1 ]; then
        warn "dry-run 下跳过安装后版本读取"
    else
        warn "未能读取 OpenClaw 本地版本信息"
    fi

    ensure_openclaw_dist_layout || return $?
}

apply_patches() {
    warn "[4/5] 正在应用 Termux 兼容补丁..."
    require_termux_runtime || return $?

    if ! is_termux_environment && [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过真实 Termux 兼容补丁"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ] && { [ "$DEPENDENCY_INSTALL_PENDING" -eq 1 ] || [ "$OPENCLAW_INSTALL_PENDING" -eq 1 ]; }; then
        warn "dry-run 下检测到依赖或 OpenClaw 尚未真实安装，跳过兼容补丁阶段"
        return 0
    fi

    if [ ! -d "$OPENCLAW_BASE_DIR" ]; then
        die "OpenClaw 安装目录不存在：$OPENCLAW_BASE_DIR"
        return $?
    fi

    patch_tmp_openclaw_paths || return $?
    patch_hardcoded_npm_path || return $?
    apply_clipboard_stub || return $?
    apply_koffi_stub || return $?
    create_openclaw_wrapper || return $?
    fix_openclaw_shebang || return $?

    success "✅ Termux 兼容补丁已处理完成"
}

setup_shell_integration() {
    local env_content=""
    local shell_block=""
    local runtime_functions=""

    warn "[5/5] 正在写入 shell 集成与运行环境..."
    require_termux_runtime || return $?

    env_content="$(render_openclaw_env_content)"
    shell_block="$(render_openclaw_shell_block)"
    runtime_functions="$(render_openclaw_runtime_functions)"

    ensure_parent_dir "$OPENCLAW_ENV_FILE" || return $?
    run_cmd touch "$BASHRC" || {
        die "无法创建或访问 $BASHRC"
        return $?
    }

    write_text_file "$OPENCLAW_ENV_FILE" "$env_content" || {
        die "写入 OpenClaw 环境文件失败：$OPENCLAW_ENV_FILE"
        return $?
    }
    run_cmd chmod 600 "$OPENCLAW_ENV_FILE" || {
        die "无法设置环境文件权限：$OPENCLAW_ENV_FILE"
        return $?
    }

    remove_openclaw_shell_block || return $?
    append_text_file "$BASHRC" "$shell_block" || {
        die "写入 shell 配置块失败：$BASHRC"
        return $?
    }

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过当前 shell 即时生效，仅展示将写入的 shell 集成配置"
        success "✅ shell 集成配置已完成模拟写入"
        return 0
    fi

    if [ -f "$OPENCLAW_ENV_FILE" ]; then
        . "$OPENCLAW_ENV_FILE"
    fi
    append_path_for_current_shell
    export TMPDIR="$TMP_DIR"

    if [ "$SCRIPT_SOURCED" -eq 1 ]; then
        eval "$runtime_functions" || {
            die "无法在当前 shell 中注入 ocr/oclog/ockill 函数"
            return $?
        }
        success "✅ 当前 shell 已同步加载 ocr / oclog / ockill"
    else
        warn "当前是独立 bash 执行；如需立刻使用 ocr / oclog / ockill，请手动执行：source ~/.bashrc"
    fi

    success "✅ shell 集成与运行环境已写入"
}

start_service() {
    local restart_choice="y"
    local running_process=""
    local has_tmux_session="no"
    local gateway_cmd=""

    warn "正在启动 OpenClaw 服务..."
    require_termux_runtime || return $?

    if [ "$DRY_RUN" -eq 1 ] && ! is_termux_environment; then
        warn "dry-run 下跳过真实服务启动"
        return 0
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过真实服务启动"
        return 0
    fi

    if ! command -v tmux >/dev/null 2>&1; then
        die "未检测到 tmux，无法启动后台服务"
        return $?
    fi
    if [ ! -x "$OPENCLAW_BIN" ]; then
        die "OpenClaw 可执行文件不存在：$OPENCLAW_BIN"
        return $?
    fi

    if command -v termux-wake-lock >/dev/null 2>&1; then
        termux-wake-lock 2>/dev/null || warn "termux-wake-lock 执行失败，设备可能仍会休眠"
    else
        warn "未检测到 termux-wake-lock，跳过唤醒锁激活"
    fi

    running_process="$(find_openclaw_gateway_processes)"
    if tmux has-session -t openclaw 2>/dev/null; then
        has_tmux_session="yes"
    fi

    if [ -n "$running_process" ] || [ "$has_tmux_session" = "yes" ]; then
        warn "检测到已有 OpenClaw 实例在运行"
        restart_choice=$(confirm_with_default "是否停止旧实例并启动新实例? (y/n) [默认: y]: " "y")
        if [ "$restart_choice" != "y" ]; then
            warn "保留当前实例运行，跳过启动"
            return 0
        fi

        stop_openclaw_gateway_service
    fi

    run_cmd mkdir -p "$TMP_DIR" "$LOG_DIR" || {
        die "无法准备运行目录：$TMP_DIR 或 $LOG_DIR"
        return $?
    }
    append_path_for_current_shell
    export TMPDIR="$TMP_DIR"
    export OPENCLAW_GATEWAY_TOKEN="$TOKEN"
    export OPENCLAW_PORT="$PORT"
    export OPENCLAW_AUTO_START="$AUTO_START"

    gateway_cmd="$(build_gateway_tmux_command)"
    run_cmd tmux new-session -d -s openclaw "$gateway_cmd" || {
        die "tmux 会话创建失败，无法启动 OpenClaw"
        return $?
    }

    sleep 2
    if ! tmux has-session -t openclaw 2>/dev/null; then
        die "tmux 会话启动后立即退出，请检查 $LOG_DIR/runtime.log"
        return $?
    fi

    success "✅ OpenClaw Gateway 服务已启动"
    info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
}

run_onboard() {
    local onboard_choice="y"
    local old_ld_preload="${LD_PRELOAD:-}"
    local onboard_status=0
    local config_path="$HOME/.openclaw/openclaw.json"
    local token_ref='${OPENCLAW_GATEWAY_TOKEN}'

    if [ "$DRY_RUN" -eq 1 ]; then
        warn "dry-run 下跳过真实 onboard 引导"
        return 0
    fi

    if [ "$FORCE_UPDATE" -eq 1 ]; then
        success "✅ 更新完成；如需重新配置模型，可稍后手动执行 openclaw onboard"
        info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
        return 0
    fi

    if [ "$NON_INTERACTIVE" -eq 1 ] || ! [ -t 0 ]; then
        warn "非交互模式下跳过 onboard，请稍后手动执行 openclaw onboard"
        info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
        return 0
    fi

    if ! tmux has-session -t openclaw 2>/dev/null; then
        die "服务启动失败，请检查 $LOG_DIR/runtime.log 后再执行 openclaw onboard"
        return $?
    fi

    echo ""
    info "请准备好大模型 API Key，中国大陆可优先考虑 MiniMax、智谱等供应商。"
    warn "如果 onboard 结束后看到 'Gateway service install not supported on android'，可以忽略。"
    warn "不要手动执行 openclaw gateway，日常请使用 ocr / oclog / ockill。"
    echo ""

    onboard_choice=$(confirm_with_default "是否现在继续执行 openclaw onboard? (y/n) [默认: y]: " "y")
    if [ "$onboard_choice" != "y" ]; then
        warn "已跳过 onboard，可稍后手动执行 openclaw onboard"
        info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
        return 0
    fi

    log "RUN: openclaw onboard"
    append_path_for_current_shell
    export TMPDIR="$TMP_DIR"
    unset LD_PRELOAD
    openclaw onboard
    onboard_status=$?
    if [ -n "$old_ld_preload" ]; then
        export LD_PRELOAD="$old_ld_preload"
    fi

    if [ "$onboard_status" -ne 0 ]; then
        warn "openclaw onboard 非 0 退出（$onboard_status），请根据界面提示确认是否已完成配置"
    fi

    if [ ! -f "$config_path" ]; then
        warn "未检测到 $config_path，后续可手动执行 openclaw onboard"
        info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
        return 0
    fi

    env CONFIG_PATH="$config_path" node -e "const fs=require('fs'); JSON.parse(fs.readFileSync(process.env.CONFIG_PATH,'utf8'));" 2>/dev/null || {
        warn "检测到 openclaw.json，但格式无效；请手动检查后重新执行 openclaw onboard"
        info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
        return 0
    }

    env CONFIG_PATH="$config_path" TOKEN_REF="$token_ref" node -e "const fs=require('fs'); const p=process.env.CONFIG_PATH; const data=JSON.parse(fs.readFileSync(p,'utf8')); data.gateway=data.gateway||{}; data.gateway.auth=data.gateway.auth||{}; data.gateway.auth.token=process.env.TOKEN_REF; fs.writeFileSync(p, JSON.stringify(data, null, 2)+'\\n');" || {
        warn "openclaw.json 已生成，但 token 环境变量引用写回失败"
        info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
        return 0
    }

    stop_openclaw_gateway_service

    start_service || {
        warn "onboard 后自动重启服务失败，请手动执行 ocr"
        info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
        return 0
    }

    success "✅ onboard 已完成，Gateway Token 已切换为环境变量引用"
    info "浏览器访问：http://localhost:$PORT/?token=$TOKEN"
    echo "常用命令：ocr（重启） / oclog（查看会话） / ockill（停止）"
}

uninstall_openclaw() {
    local config_path="$HOME/.openclaw/openclaw.json"
    local backup_path=""

    warn "正在卸载 OpenClaw..."

    warn "[UNINSTALL 1/5] 正在停止服务与后台会话..."
    stop_openclaw_gateway_service

    warn "[UNINSTALL 2/5] 正在清理 shell 集成与环境文件..."
    remove_openclaw_shell_block || return $?
    if [ -f "$OPENCLAW_ENV_FILE" ] || [ "$DRY_RUN" -eq 1 ]; then
        run_cmd rm -f "$OPENCLAW_ENV_FILE" || {
            die "无法删除环境文件：$OPENCLAW_ENV_FILE"
            return $?
        }
    else
        info "未检测到环境文件，跳过：$OPENCLAW_ENV_FILE"
    fi
    if [ "$SCRIPT_SOURCED" -eq 1 ]; then
        cleanup_current_shell_openclaw_runtime || return $?
    fi

    warn "[UNINSTALL 3/5] 正在卸载 OpenClaw 全局包..."
    if [ "$DRY_RUN" -eq 1 ] || command -v npm >/dev/null 2>&1; then
        run_cmd npm uninstall -g "$OPENCLAW_PACKAGE" || warn "npm uninstall 返回非 0，可能尚未安装 OpenClaw"
    else
        warn "未检测到 npm，跳过全局包卸载"
    fi

    warn "[UNINSTALL 4/5] 正在清理运行状态与配置..."
    run_cmd rm -f "$UPDATE_FLAG" || warn "更新标记删除失败：$UPDATE_FLAG"
    if [ -f "$config_path" ]; then
        backup_path="$config_path.$(date +%Y%m%d_%H%M%S).bak"
        run_cmd cp "$config_path" "$backup_path" || {
            die "备份 openclaw.json 失败：$backup_path"
            return $?
        }
        run_cmd rm -f "$config_path" || {
            die "无法删除配置文件：$config_path"
            return $?
        }
        success "✅ 已备份并删除 openclaw.json：$backup_path"
    else
        info "未检测到 openclaw.json，跳过备份与删除"
    fi

    warn "[UNINSTALL 5/5] 正在清理日志目录..."
    if [ -d "$LOG_DIR" ] || [ "$DRY_RUN" -eq 1 ]; then
        run_cmd rm -rf "$LOG_DIR" || {
            die "无法删除日志目录：$LOG_DIR"
            return $?
        }
    else
        info "未检测到日志目录，跳过：$LOG_DIR"
    fi

    success "✅ OpenClaw 卸载流程已完成"
    warn "说明：已保留 $NPM_GLOBAL 目录中可能存在的其他全局包，仅尝试卸载 openclaw 本身。"

    return 0
}

main() {
    init_colors
    parse_args "$@" || return $?

    if [ "$SHOW_HELP" -eq 1 ]; then
        show_help
        return 0
    fi

    if [ "$LIST_VERSIONS" -eq 1 ]; then
        list_openclaw_versions
        return 0
    fi

    print_banner
    if [ "$DRY_RUN" -eq 1 ]; then
        warn "🔍 当前为模拟运行模式"
    fi
    if [ "$VERBOSE" -eq 1 ]; then
        info "详细输出模式已启用"
    fi
    if [ "$UNINSTALL" -eq 1 ]; then
        uninstall_openclaw || return $?
        return 0
    fi

    collect_inputs || return $?
    show_phase2_summary

    check_deps || return $?
    configure_npm || return $?
    install_or_update_openclaw || return $?
    apply_patches || return $?
    setup_shell_integration || return $?
    start_service || return $?
    run_onboard || return $?

    success "✅ v2 主流程已完成：安装、补丁、shell 集成、服务启动与 onboard 引导均已接入。"

    return 0
}

main "$@"
MAIN_EXIT_CODE=$?

if [ "$SCRIPT_SOURCED" -eq 1 ]; then
    return "$MAIN_EXIT_CODE"
fi

exit "$MAIN_EXIT_CODE"