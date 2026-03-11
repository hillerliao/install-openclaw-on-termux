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

# 2. 安装 Ubuntu（检测可用发行版并安装）
echo "2. 安装并准备 proot-distro 的 Ubuntu"

# 检查已安装的发行版
INSTALLED=$(proot-distro list --installed 2>/dev/null || ls ~/.proot-distro/installed-rootfs/ 2>/dev/null || echo "")

# 检查 ubuntu 是否已安装
if echo "$INSTALLED" | grep -q "ubuntu"; then
  echo "Ubuntu 发行版已安装，跳过安装步骤"
  DISTRO="ubuntu"
else
  # 优先安装 ubuntu-22.04, 回退到 ubuntu-20.04 或 ubuntu
  AVAILABLE=$(proot-distro list || true)
  if echo "$AVAILABLE" | grep -q "ubuntu-22.04"; then
    DISTRO="ubuntu-22.04"
  elif echo "$AVAILABLE" | grep -q "ubuntu-20.04"; then
    DISTRO="ubuntu-20.04"
  else
    DISTRO="ubuntu"
  fi
  echo "选择安装发行版: $DISTRO"
  if ! proot-distro install "$DISTRO"; then
    echo "安装 $DISTRO 失败，尝试回退到 ubuntu..."
    DISTRO="ubuntu"
    proot-distro install "$DISTRO" || echo "Ubuntu 可能已安装，继续..."
  fi
fi

# 3. 进入 Ubuntu 并执行后续命令（在 proot 内部执行）
proot-distro login "$DISTRO" -- bash -s <<'PROOT_BASH'
set -euo pipefail
echo "进入 proot-distro: $(date)"

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

# 根据架构和版本选择源（优先使用 HTTPS，并探测当前 codename/arch 是否可用）
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
  echo "arm64 架构，探测可用的 ubuntu-ports HTTPS 镜像"
  MIRROR_CANDIDATES=(
    "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
    "https://mirrors.ustc.edu.cn/ubuntu-ports"
    "https://ports.ubuntu.com/ubuntu-ports"
  )
else
  echo "$ARCH 架构，探测可用的 Ubuntu HTTPS 镜像"
  MIRROR_CANDIDATES=(
    "https://mirrors.tuna.tsinghua.edu.cn/ubuntu"
    "https://mirrors.ustc.edu.cn/ubuntu"
    "https://archive.ubuntu.com/ubuntu"
  )
fi

MIRROR_URL=""
for candidate in "${MIRROR_CANDIDATES[@]}"; do
  TEST_URL="$candidate/dists/$CODENAME/main/binary-$ARCH/Packages.gz"
  echo "测试镜像: $TEST_URL"
  if curl -fsI -L --connect-timeout 8 --max-time 20 "$TEST_URL" >/dev/null 2>&1; then
    MIRROR_URL="$candidate"
    echo "使用镜像: $MIRROR_URL"
    break
  fi
done

if [ -z "$MIRROR_URL" ]; then
  if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    MIRROR_URL="https://ports.ubuntu.com/ubuntu-ports"
  else
    MIRROR_URL="https://archive.ubuntu.com/ubuntu"
  fi
  echo "警告：镜像探测失败，回退到: $MIRROR_URL"
fi

# 写入源
cat > /etc/apt/sources.list <<OPENCLAW_SOURCES_LIST_EOF
deb $MIRROR_URL $CODENAME main restricted universe multiverse
deb $MIRROR_URL $CODENAME-updates main restricted universe multiverse
deb $MIRROR_URL $CODENAME-backports main restricted universe multiverse
deb $MIRROR_URL $CODENAME-security main restricted universe multiverse
OPENCLAW_SOURCES_LIST_EOF

apt update
apt upgrade -y

# 4. 安装构建与运行时依赖（nvm/node 编译需要）
apt install -y curl build-essential git wget nano ca-certificates python3 python3-pip gnupg lsb-release

# 5. 安装 nvm 并切换 Node.js 22.x
export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
# 显式加载 nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
# 安装 Node 22（安装最新 22.x）
nvm install 22
nvm alias default 22
nvm use 22

# 6. 安装 OpenClaw（全局）
npm config set fund false
npm install -g openclaw

# 7. 创建 hijack.js 脚本（确保目录存在）
mkdir -p "$HOME/.openclaw"
cat > "$HOME/.openclaw/hijack.js" <<'OPENCLAW_HIJACK_JS_EOF'
const Module = require('module');
const os = require('node:os');
const originalRequire = Module.prototype.require;
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

Module.prototype.require = function(path) {
  if (path === 'child_process') {
    return {
      spawn: () => { throw new Error('spawn disabled'); },
      exec: () => { throw new Error('exec disabled'); },
      execSync: () => { throw new Error('execSync disabled'); }
    };
  }
  return originalRequire.apply(this, arguments);
};
OPENCLAW_HIJACK_JS_EOF

# 8. 启动 OpenClaw 网关（后台运行），查找 openclaw 可执行路径
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
REAL_OPENCLAW_BIN="${OPENCLAW_BIN}.proot-real"
if ! grep -q 'OPENCLAW_PROOT_WRAPPER' "$OPENCLAW_BIN" 2>/dev/null; then
  rm -f "$REAL_OPENCLAW_BIN"
  mv "$OPENCLAW_BIN" "$REAL_OPENCLAW_BIN"
fi
cat > "$OPENCLAW_BIN" <<OPENCLAW_WRAPPER_EOF
#!/usr/bin/env bash
# OPENCLAW_PROOT_WRAPPER
export NODE_OPTIONS="--require=$HOME/.openclaw/hijack.js\${NODE_OPTIONS:+ \$NODE_OPTIONS}"
exec "$REAL_OPENCLAW_BIN" "\$@"
OPENCLAW_WRAPPER_EOF
chmod +x "$OPENCLAW_BIN"

# 确保 nohup 可用，否则使用 setsid
if command -v nohup >/dev/null 2>&1; then
  nohup "$OPENCLAW_BIN" gateway > "$HOME/openclaw_gateway.log" 2>&1 &
else
  setsid "$OPENCLAW_BIN" gateway > "$HOME/openclaw_gateway.log" 2>&1 &
fi

echo "OpenClaw gateway 已后台启动，日志: $HOME/openclaw_gateway.log"
sleep 5
# 检查进程是否存活（匹配 node 进程运行的 openclaw）
if pgrep -f "node.*openclaw" >/dev/null 2>&1; then
  echo "✓ OpenClaw 进程运行正常"
else
  echo "⚠ 警告：OpenClaw 进程可能未成功启动，请检查日志: $HOME/openclaw_gateway.log"
fi
echo "进入 proot-distro 完成。"
PROOT_BASH

echo "部署脚本执行结束：$(date)"
echo "请在 Ubuntu 环境内完成 Token 配置与 Termux 存储授权（如需要）。日志文件：$LOGFILE"