#!/usr/bin/env bash
set -euo pipefail

LOGFILE="$HOME/deploy_openclaw_proot.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "开始部署：$(date)"

# 0. Termux 存储授权提示（需要用户手动授权）
echo "如果尚未授权 Termux 存储，请在新终端运行: termux-setup-storage 并授权后再运行本脚本。"
# 不自动调用 termux-setup-storage 以避免非交互阻塞

# 1. 更新 Termux 包
echo "1. 更新 Termux 包"
pkg update -y
# 避免在 `curl | bash` 过程中升级当前正在运行的 bash，
# 这会触发 bash.bashrc 交互式 conffile 提示，并可能打断后续脚本执行。
pkg install proot-distro git curl wget nano -y

# 2. 安装 Ubuntu（自动决定可用发行版，不要求用户选择版本）
echo "2. 安装并准备 proot-distro 的 Ubuntu"

# 检查已安装的发行版（不同版本 proot-distro 的安装目录可能不同）
INSTALLED_NAMES=""
for installed_rootfs_dir in \
  "$PREFIX/var/lib/proot-distro/installed-rootfs" \
  "$HOME/.proot-distro/installed-rootfs"
do
  if [ -d "$installed_rootfs_dir" ]; then
    INSTALLED_NAMES=$(ls -1 "$installed_rootfs_dir" 2>/dev/null || true)
    break
  fi
done

# 优先复用已安装的 Ubuntu 发行版
DISTRO=""
for candidate in ubuntu ubuntu-24.04 ubuntu-22.04 ubuntu-20.04; do
  if printf '%s\n' "$INSTALLED_NAMES" | grep -qx "$candidate"; then
    DISTRO="$candidate"
    break
  fi
done

if [ -n "$DISTRO" ]; then
  echo "检测到已安装 Ubuntu 发行版: $DISTRO，跳过安装步骤"
else
  AVAILABLE=$(proot-distro list 2>/dev/null || true)
  AVAILABLE_NAMES=$(printf '%s\n' "$AVAILABLE" | sed -n 's/.*< *\([^>]*\) *>.*/\1/p' | sed 's/[[:space:]]*$//')

  # 优先使用通用 ubuntu，只有在其不可用时才自动回退到版本化条目
  for candidate in ubuntu ubuntu-24.04 ubuntu-22.04 ubuntu-20.04; do
    if printf '%s\n' "$AVAILABLE_NAMES" | grep -qx "$candidate"; then
      DISTRO="$candidate"
      break
    fi
  done

  if [ -z "$DISTRO" ]; then
    DISTRO="ubuntu"
  fi

  echo "自动使用 Ubuntu 发行版: $DISTRO"
  if ! proot-distro install "$DISTRO"; then
    if [ "$DISTRO" != "ubuntu" ]; then
      echo "安装 $DISTRO 失败，尝试回退到 ubuntu..."
      DISTRO="ubuntu"
      proot-distro install "$DISTRO" || echo "Ubuntu 可能已安装，继续..."
    else
      echo "安装 ubuntu 失败，继续尝试后续步骤..."
    fi
  fi
fi

# 3. 进入 Ubuntu 并执行后续命令（在 proot 内部执行）
OPENCLAW_TERMUX_DISTRO="$DISTRO" proot-distro login "$DISTRO" -- bash -s <<'PROOT_BASH'
set -euo pipefail
echo "进入 proot-distro: $(date)"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

if ! [ -t 1 ] || [ "$(tput colors 2>/dev/null || echo 0)" -lt 8 ]; then
  GREEN=''
  BLUE=''
  YELLOW=''
  RED=''
  CYAN=''
  NC=''
fi

DISTRO_NAME="${OPENCLAW_TERMUX_DISTRO:-ubuntu}"

# 3.1 备份并替换 Ubuntu 源（根据发行版动态配置）
if [ -f /etc/apt/sources.list ]; then
  cp /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s)
fi
# 检测当前 Ubuntu 版本代号（优先从 os-release 读取）
CODENAME=$(grep -oP 'VERSION_CODENAME=\K.*' /etc/os-release 2>/dev/null || grep -oP 'UBUNTU_CODENAME=\K.*' /etc/os-release 2>/dev/null || lsb_release -cs 2>/dev/null || echo "jammy")
echo "检测到 Ubuntu 代号: $CODENAME"

# 检测当前架构
ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
echo "检测到架构: $ARCH"

# 根据架构和版本选择源（优先使用 HTTPS，并用 apt-get update 实测可用性）
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
  echo "arm64 架构，探测可用的 ubuntu-ports HTTPS 镜像"
  MIRROR_CANDIDATES=(
    "https://mirrors.ustc.edu.cn/ubuntu-ports"
    "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
    "https://ports.ubuntu.com/ubuntu-ports"
  )
else
  echo "$ARCH 架构，探测可用的 Ubuntu HTTPS 镜像"
  MIRROR_CANDIDATES=(
    "https://mirrors.ustc.edu.cn/ubuntu"
    "https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
    "https://archive.ubuntu.com/ubuntu"
  )
fi

write_sources_list() {
  local mirror_url="$1"
  cat > /etc/apt/sources.list <<OPENCLAW_SOURCES_LIST_EOF
deb $mirror_url $CODENAME main restricted universe multiverse
deb $mirror_url $CODENAME-updates main restricted universe multiverse
deb $mirror_url $CODENAME-backports main restricted universe multiverse
deb $mirror_url $CODENAME-security main restricted universe multiverse
OPENCLAW_SOURCES_LIST_EOF
}

apt_update_cleanly() {
  local log_file="$1"
  if DEBIAN_FRONTEND=noninteractive apt-get update 2>&1 | tee "$log_file"; then
    if ! grep -Eiq 'Failed to fetch|Unable to connect|Could not connect|Some index files failed to download' "$log_file"; then
      return 0
    fi
  fi
  return 1
}

MIRROR_URL=""
for candidate in "${MIRROR_CANDIDATES[@]}"; do
  TEST_URL="$candidate/dists/$CODENAME/main/binary-$ARCH/Packages.gz"
  echo "测试镜像: $TEST_URL"
  write_sources_list "$candidate"
  APT_UPDATE_LOG="$(mktemp)"
  if apt_update_cleanly "$APT_UPDATE_LOG"; then
    MIRROR_URL="$candidate"
    echo "使用镜像: $MIRROR_URL"
    rm -f "$APT_UPDATE_LOG"
    break
  fi
  echo "镜像不可用，尝试下一个: $candidate"
  rm -f "$APT_UPDATE_LOG"
done

if [ -z "$MIRROR_URL" ]; then
  if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    MIRROR_URL="https://ports.ubuntu.com/ubuntu-ports"
  else
    MIRROR_URL="https://archive.ubuntu.com/ubuntu"
  fi
  echo "警告：镜像探测失败，回退到: $MIRROR_URL"
fi

# 写入最终选定的源，并再次刷新索引
write_sources_list "$MIRROR_URL"
FINAL_APT_UPDATE_LOG="$(mktemp)"
if ! apt_update_cleanly "$FINAL_APT_UPDATE_LOG"; then
  echo "错误：最终 apt-get update 失败，无法继续安装依赖。"
  cat "$FINAL_APT_UPDATE_LOG"
  rm -f "$FINAL_APT_UPDATE_LOG"
  exit 1
fi
rm -f "$FINAL_APT_UPDATE_LOG"
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# 4. 安装构建与运行时依赖（nvm/node 编译需要）
DEBIAN_FRONTEND=noninteractive apt-get install -y curl build-essential git wget nano ca-certificates python3 python3-pip gnupg lsb-release

# 5. 安装 nvm 并切换 Node.js 22.x
export NVM_DIR="$HOME/.nvm"
install_nvm() {
  echo "安装/重装 nvm..."
  rm -rf "$NVM_DIR"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | PROFILE=/dev/null bash
}

load_nvm() {
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] || return 1
  unset -f nvm 2>/dev/null || true
  . "$NVM_DIR/nvm.sh"
  command -v nvm >/dev/null 2>&1
}

if ! load_nvm; then
  echo "检测到 nvm 不可用，尝试重新安装..."
  install_nvm
  load_nvm || { echo "错误：nvm 安装/加载失败，nvm 仍不可用"; exit 1; }
fi

# 安装 Node 22（安装最新 22.x）
nvm install 22
nvm alias default 22
nvm use 22
NODE_EXE="$(command -v node)"
NODE_BIN_DIR="$(dirname "$(command -v node)")"

# 让后续登录 shell 也能直接使用 node/npm/openclaw
mkdir -p /etc/profile.d
cat > /etc/profile.d/openclaw-nvm.sh <<OPENCLAW_NVM_PROFILE_EOF
export NVM_DIR="\$HOME/.nvm"
if [ -s "\$NVM_DIR/nvm.sh" ]; then
  . "\$NVM_DIR/nvm.sh" >/dev/null 2>&1 || true
fi
case ":\$PATH:" in
  *:"$NODE_BIN_DIR":*) ;;
  *) export PATH="$NODE_BIN_DIR:\$PATH" ;;
esac
OPENCLAW_NVM_PROFILE_EOF
chmod 644 /etc/profile.d/openclaw-nvm.sh

# 6. 安装 OpenClaw（全局）
npm config set fund false
npm install -g openclaw

# 7. 创建 hijack.js 脚本（确保目录存在）
mkdir -p "$HOME/.openclaw"
cat > "$HOME/.openclaw/hijack.js" <<'OPENCLAW_HIJACK_JS_EOF'
const Module = require('module');
const os = require('node:os');
const originalNetworkInterfaces = os.networkInterfaces.bind(os);

os.networkInterfaces = function patchedNetworkInterfaces() {
  try {
    return originalNetworkInterfaces();
  } catch (err) {
    const fallbackIp = process.env.OPENCLAW_PROOT_IPV4 || '127.0.0.1';
    return {
      eth0: [{
        address: fallbackIp,
        netmask: '255.0.0.0',
        family: 'IPv4',
        mac: '00:00:00:00:00:00',
        internal: false,
        cidr: fallbackIp + '/8'
      }],
      lo: [{
        address: '127.0.0.1',
        netmask: '255.0.0.0',
        family: 'IPv4',
        mac: '00:00:00:00:00:00',
        internal: true,
        cidr: '127.0.0.1/8'
      }]
    };
  }
};

if (typeof Module.syncBuiltinESMExports === 'function') {
  Module.syncBuiltinESMExports();
}
OPENCLAW_HIJACK_JS_EOF

# 8. 查找 openclaw 可执行路径并包装命令
OPENCLAW_BIN="$(command -v openclaw || true)"
if [ -z "$OPENCLAW_BIN" ]; then
  # 尝试 npm 全局 bin 路径
  NPM_BIN_DIR="$(npm bin -g 2>/dev/null || echo "$HOME/.nvm/versions/node/$(node -v)/bin")"
  OPENCLAW_BIN="$NPM_BIN_DIR/openclaw"
fi
if [ ! -x "$OPENCLAW_BIN" ] && [ ! -f "$OPENCLAW_BIN" ]; then
  echo "错误：找不到 openclaw 可执行文件，安装可能失败。"
  echo "已搜索路径: $OPENCLAW_BIN"
  exit 1
fi
echo "找到 openclaw: $OPENCLAW_BIN"

# 8.1 包装 openclaw 命令，确保所有 CLI 子命令都自动加载 proot shim
if [ -L "$OPENCLAW_BIN" ]; then
  REAL_OPENCLAW_BIN="$(readlink -f "$OPENCLAW_BIN")"
  rm -f "$OPENCLAW_BIN"
else
  REAL_OPENCLAW_BIN="${OPENCLAW_BIN}.proot-real"
  if ! grep -q 'OPENCLAW_PROOT_WRAPPER' "$OPENCLAW_BIN" 2>/dev/null; then
    rm -f "$REAL_OPENCLAW_BIN"
    mv "$OPENCLAW_BIN" "$REAL_OPENCLAW_BIN"
  fi
fi
cat > "$OPENCLAW_BIN" <<OPENCLAW_WRAPPER_EOF
#!/usr/bin/env bash
# OPENCLAW_PROOT_WRAPPER
export PATH="$NODE_BIN_DIR:\$PATH"
export NODE_OPTIONS="--require=$HOME/.openclaw/hijack.js\${NODE_OPTIONS:+ \$NODE_OPTIONS}"
exec "$NODE_EXE" "$REAL_OPENCLAW_BIN" "\$@"
OPENCLAW_WRAPPER_EOF
chmod +x "$OPENCLAW_BIN"
mkdir -p /usr/local/bin
ln -sf "$OPENCLAW_BIN" /usr/local/bin/openclaw

is_openclaw_config_ready() {
  [ -f "$HOME/.openclaw/openclaw.json" ] || return 1
  node -e "JSON.parse(require('fs').readFileSync(process.env.HOME + '/.openclaw/openclaw.json','utf8'))" >/dev/null 2>&1
}

show_resume_tip() {
  local state="${1:-needs_onboard}"
  echo
  echo -e "${BLUE}==========================================${NC}"
  echo -e "${GREEN}✅ OpenClaw 已安装完成${NC}"
  echo -e "${BLUE}==========================================${NC}"
  if [ "$state" = "configured" ]; then
    echo "首次配置已经完成。"
    echo "下次打开时：先进入 Ubuntu，再运行 openclaw gateway。"
    echo "如果要进入对话界面，可新开一个 Termux 会话后执行 openclaw tui。"
  else
    echo "安装已经完成，还差最后一步首次配置。"
    echo "下次打开时：先进入 Ubuntu，再运行 openclaw onboard。"
  fi
  echo "进入 Ubuntu 的命令：proot-distro login $DISTRO_NAME"
  echo "提示：不要把 Termux 从后台划掉，否则 OpenClaw 进程也会一起结束。"
}

echo
echo -e "${BLUE}==========================================${NC}"
echo -e "${GREEN}✅ OpenClaw 安装完成${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "${CYAN}接下来可以直接开始首次配置，不需要你自己再记命令。${NC}"

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
  echo "当前不是交互终端，已跳过首次配置引导。"
  show_resume_tip "needs_onboard"
  echo "进入 proot-distro 完成。"
  exit 0
fi

echo "配置时请准备好你的模型 API Key。"
echo "如果看到 systemd 相关提示，在 proot 环境里通常可以先忽略。"
echo
read -r -p "现在开始首次配置（openclaw onboard）吗？[Y/n]: " START_ONBOARD < /dev/tty || START_ONBOARD="n"
START_ONBOARD="${START_ONBOARD:-y}"

if [[ "$START_ONBOARD" =~ ^[Yy]$ ]]; then
  echo
  echo -e "${YELLOW}即将进入 openclaw onboard 配置界面...${NC}"
  echo "如果中途想稍后再配，按 Ctrl+C 退出即可。"
  read -r -p "按回车继续..." _ < /dev/tty || true
  echo

  if openclaw onboard < /dev/tty > /dev/tty 2>&1 && is_openclaw_config_ready; then
    echo
    echo -e "${GREEN}✅ 首次配置已完成。${NC}"
    read -r -p "是否现在启动 OpenClaw gateway？[Y/n]: " START_GATEWAY < /dev/tty || START_GATEWAY="n"
    START_GATEWAY="${START_GATEWAY:-y}"

    if [[ "$START_GATEWAY" =~ ^[Yy]$ ]]; then
      echo
      echo -e "${YELLOW}正在启动 openclaw gateway（前台运行，按 Ctrl+C 可退出）...${NC}"
      echo
      if openclaw gateway < /dev/tty > /dev/tty 2>&1; then
        :
      else
        echo
        echo -e "${YELLOW}OpenClaw gateway 已退出。${NC}"
      fi
    fi

    show_resume_tip "configured"
  else
    echo
    echo -e "${YELLOW}已退出首次配置，稍后还可以继续。${NC}"
    show_resume_tip "needs_onboard"
  fi
else
  echo
  echo "好的，这次先只完成安装。"
  show_resume_tip "needs_onboard"
fi

echo "进入 proot-distro 完成。"
PROOT_BASH

echo "部署脚本执行结束：$(date)"
echo "部署日志文件：$LOGFILE"