# Openclaw Termux One-Click Deployment Script

> 🦞 Deploy Openclaw in Android Termux environment with one click, allowing you to easily run AI gateway services on mobile devices

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Termux](https://img.shields.io/badge/platform-Termux-green.svg)](https://termux.com/)
[![Node.js](https://img.shields.io/badge/node-%3E%3D22.0.0-brightgreen.svg)](https://nodejs.org/)
[![English](https://img.shields.io/badge/lang-English-blue.svg)](README.en.md)
[![中文](https://img.shields.io/badge/lang-中文-red.svg)](README.md)

## 📖 Table of Contents

- [Project Overview](#project-overview)
- [Features](#features)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Detailed Usage](#detailed-usage)
- [Configuration](#configuration)
- [Common Commands](#common-commands)
- [Troubleshooting](#troubleshooting)
- [Uninstall Guide](#uninstall-guide)
- [Technical Details](#technical-details)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

---

## Project Overview

Openclaw is a powerful AI gateway service. This script is specifically designed to deploy Openclaw in the Android Termux environment. Through an automated installation process, it resolves many compatibility issues in the Termux environment, including:

- ✅ Automatically checks and installs all necessary dependency packages
- ✅ Automatically applies Android compatibility patches (log paths, clipboard, etc.)
- ✅ Configures NPM global environment and mirror sources
- ✅ Sets up Termux wake lock to prevent sleep
- ✅ Uses tmux for background persistent running
- ✅ Provides convenient alias commands for service management

---

## Features

### 🚀 One-Click Deployment

```bash
curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh
```

### 🔧 Automated Configuration

- **Dependency Check**: Automatically detects and installs Node.js, Git, CMake, and other necessary components
- **Version Verification**: Ensures Node.js version ≥ 22
- **Mirror Acceleration**: Automatically configures NPM mirror to domestic mirror
- **Compatibility Patches**:
  - Fix Logger path (`/tmp/openclaw` → `$HOME/openclaw-logs`)
  - Fix clipboard module (Termux environment compatible)
  - Create `/tmp` symbolic link

### 💪 High Availability

- **Wake Lock**: Automatically activates Termux wake lock to prevent system sleep
- **Background Running**: Uses tmux for service persistence
- **Auto Restart**: Provides one-click restart command
- **Log Management**: Real-time logging and viewing

### 🛡️ Security Mechanisms

- **Token Authentication**: Supports custom access tokens
- **Port Configuration**: Customizable Gateway port
- **SSH Service**: Optional automatic SSHD startup

### 📊 Monitoring and Management

- **Real-time Logs**: View running status via `oclog` command
- **Service Control**: Provides start, stop, and restart shortcuts
- **Detailed Logs**: Complete installation and runtime log records

---

## System Requirements

| Component | Requirement |
|-----------|-------------|
| **Operating System** | Android 7.0+ |
| **Termux** | Latest version (recommended to install via F-Droid) |
| **Node.js** | ≥ 22.0.0 (script will automatically check) |
| **Storage** | ≥ 500MB available space |
| **Memory** | ≥ 2GB RAM recommended |
| **Network** | Stable network connection (for downloading dependencies) |

### Termux Component Requirements

The script will automatically install the following Termux components (if not installed):

- `nodejs` - Node.js runtime
- `git` - Version control tool
- `openssh` - SSH client/server
- `tmux` - Terminal multiplexer
- `termux-api` - Termux API extension
- `termux-tools` - Termux toolset
- `cmake` - Build tool
- `python` - Python interpreter
- `golang` - Go language support

---

## Quick Start

### Method 1: Online Installation (Recommended)

```bash
curl -sL https://s.zhihai.me/openclaw > openclaw-install.sh && source openclaw-install.sh
```

### Method 2: Local Installation

```bash
# 1. Clone or download the script
git clone https://github.com/yourusername/install-openclaw-on-termux.sh.git
cd install-openclaw-on-termux.sh

# 2. Run the installation script
source install-openclaw-termux.sh
```

### Interactive Configuration

During installation, the script will prompt you to enter the following configuration:

```
Please enter Gateway port [default: 18789]:
Please enter custom Token (for secure access, recommend strong password) [leave empty for random generation]:
Do you need to enable auto-start on boot? (y/n) [default: y]:
```

**Recommended Configuration**:
- Port: Use default `18789` or customize
- Token: **Recommend manually entering a strong password**, or let the script generate a random token
- Auto-start: Recommend `y` for first installation, can be modified later via script

---

## Detailed Usage

### Command Line Options

```bash
source install-openclaw-termux.sh [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help information |
| `--verbose` | `-v` | Enable verbose output, display each executed command |
| `--dry-run` | `-d` | Simulation mode, do not execute actual commands (for testing) |
| `--uninstall` | `-u` | Uninstall Openclaw and clean up configuration |

### Usage Examples

```bash
# Standard installation
source install-openclaw-termux.sh

# Verbose mode installation
source install-openclaw-termux.sh --verbose

# Dry run (no actual installation)
source install-openclaw-termux.sh --dry-run

# Uninstall Openclaw
source install-openclaw-termux.sh --uninstall

# Combined usage
source install-openclaw-termux.sh -v -d  # Verbose mode + dry run
```

### Installation Process

The script will execute the following 6 steps in sequence:

```
[1/6] Checking basic runtime environment...
      ↓
[2/6] Configuring Openclaw...
      ↓
[3/6] Applying Android compatibility patches...
      ↓
[4/6] Activating wake lock...
      ↓
[5/6] Starting service...
      ↓
[6/6] Deployment command sent
```

---

## Configuration

### Environment Variables

The script will add the following environment variables to `~/.bashrc`:

```bash
export TERMUX_VERSION=1                    # Termux identifier
export TMPDIR=$HOME/tmp                     # Temporary directory
export OPENCLAW_GATEWAY_TOKEN=your_token    # Access token
export PATH=$HOME/.npm-global/bin:$PATH     # NPM global path
```

### Directory Structure

```
$HOME/
├── .bashrc                      # Shell configuration file (script will modify)
├── .bashrc.backup               # bashrc backup (automatically created before modification)
├── .npm-global/                 # NPM global package directory
│   └── bin/                     # NPM executable directory
│       └── openclaw             # Openclaw executable
├── openclaw-logs/               # Log directory
│   ├── install.log             # Installation log
│   └── runtime.log              # Runtime log
└── tmp/                         # Temporary file directory
```

### Port Configuration

- **Default Port**: `18789`
- **Modification Method**: Re-run the script and enter a new port
- **Access Address**: `http://<deviceIP>:<port>`
- **Token Authentication**: Need to carry `Authorization: Bearer <token>` in request header

---

## Common Commands

After installation, the script will create the following shortcut aliases (if enabled in ~/.bashrc):

| Alias | Function | Usage Example |
|-------|----------|---------------|
| `ocr` | **Restart Service** | `ocr` |
| `oclog` | **View Logs** | `oclog` |
| `ockill` | **Stop Service** | `ockill` |

### Command Details

#### 1. Restart Service (`ocr`)

```bash
ocr
```

**Function**: Stop existing service and restart Openclaw Gateway

**Internal Process**:
```bash
pkill -9 node                     # Stop all Node.js processes
tmux kill-session -t openclaw     # Destroy tmux session
sleep 1                           # Wait for process cleanup
tmux new -d -s openclaw           # Create new tmux session
tmux send-keys -t openclaw "openclaw gateway --bind lan --port <port> --token <token>" C-m
```

#### 2. View Logs (`oclog`)

```bash
oclog
```

**Function**: Attach to tmux session to view Openclaw runtime logs in real-time

**Shortcuts**:
- `Ctrl+B` then `D`: Detach session (service continues running)
- `Ctrl+C`: Stop service (not recommended)

#### 3. Stop Service (`ockill`)

```bash
ockill
```

**Function**: Force stop Openclaw service

**Internal Process**:
```bash
pkill -9 node                     # Stop all Node.js processes
tmux kill-session -t openclaw     # Destroy tmux session
```

### Manual Management Commands

If you don't want to use aliases, you can also manually execute the following commands:

```bash
# View tmux session status
tmux list-sessions

# Attach to openclaw session
tmux attach -t openclaw

# Detach current session (shortcut: Ctrl+B then D)
tmux detach-client

# View real-time logs
tail -f $HOME/openclaw-logs/runtime.log
```

---

## Troubleshooting

### Installation Failures

#### Issue 1: Node.js Version Does Not Meet Requirements

**Symptom**:
```
Error: Node.js version must be 22 or higher, current version: v20.x.x
```

**Solution**:
```bash
# Update pkg source
pkg update -y

# Uninstall old Node.js
pkg uninstall nodejs

# Install latest Node.js
pkg install nodejs -y

# Verify version
node -v  # Should show v22.x.x or higher
```

#### Issue 2: pkg update Failed

**Symptom**:
```
Error: pkg update failed
```

**Solution**:
```bash
# Clear cache
pkg clean

# Change mirror (optional)
# Edit $PREFIX/etc/apt/sources.list to use Tsinghua or Aliyun mirror

# Update again
pkg update -y
```

#### Issue 3: NPM Mirror Setting Failed

**Symptom**:
```
Error: NPM mirror setting failed
```

**Solution**:
```bash
# Manually set mirror
npm config set registry https://registry.npmmirror.com

# Verify
npm config get registry
```

### Service Startup Failures

#### Issue 1: tmux Session Crashes Immediately After Startup

**Symptom**:
```
❌ Error: tmux session crashed immediately after startup.
Please check error log: cat $HOME/openclaw-logs/runtime.log
```

**Solution**:
```bash
# View detailed logs
cat $HOME/openclaw-logs/runtime.log

# Common causes and solutions:
# 1. Port occupied → Change port
# 2. Invalid token → Re-run script to set
# 3. Insufficient memory → Close other apps
```

#### Issue 2: termux-wake-lock Activation Failed

**Symptom**:
```
⚠️  Wake-lock activation failed, termux-api may not be properly installed
```

**Solution**:
```bash
# Install termux-api
pkg install termux-api -y

# Check Termux app permissions
# Settings → Permissions → Disable battery optimization → Allow Termux

# Re-activate wake lock
termux-wake-lock
```

#### Issue 3: Unable to Connect to Gateway

**Symptom**:
```bash
curl: Connection refused
```

**Solution**:
```bash
# 1. Check if service is running
tmux list-sessions

# 2. Check if port is listening
netstat -tuln | grep <port>

# 3. Check firewall (some Android devices)
# 4. Confirm using correct IP address
ip addr show wlan0

# 5. Restart service
ocr
```

### Performance Issues

#### Issue 1: Device Overheating

**Solution**:
```bash
# 1. Limit CPU usage (if supported)
# 2. Reduce Gateway concurrency
# 3. Use `oclog` to check for abnormal requests

# View resource usage
top -m 10
```

#### Issue 2: Slow Response Speed

**Solution**:
```bash
# 1. Check network connection
ping -c 4 8.8.8.8

# 2. View logs to troubleshoot bottlenecks
oclog

# 3. Clear system cache
pkg clean
```

### Log Viewing

```bash
# Installation log
cat $HOME/openclaw-logs/install.log

# Runtime log
cat $HOME/openclaw-logs/runtime.log

# Real-time log tracking
tail -f $HOME/openclaw-logs/runtime.log

# View last 50 lines
tail -n 50 $HOME/openclaw-logs/runtime.log
```

---

## Uninstall Guide

### Method 1: Uninstall Using Script

```bash
source install-openclaw-termux.sh --uninstall
```

**Uninstall Content**:
- ✅ Stop Openclaw service
- ✅ Remove Openclaw configuration from ~/.bashrc
- ✅ Uninstall Openclaw NPM package
- ✅ Delete log directory `$HOME/openclaw-logs`
- ✅ Delete NPM global directory `$HOME/.npm-global`
- ✅ Clean up temporary files

**Preserved Content**:
- ✅ Bashrc backup file (can be manually restored)

### Method 2: Manual Uninstall

```bash
# 1. Stop service
pkill -9 node
tmux kill-session -t openclaw

# 2. Remove bashrc configuration
sed -i '/# --- Openclaw Start ---/,/# --- Openclaw End ---/d' ~/.bashrc
sed -i '/export PATH=.*\.npm-global\/bin/d' ~/.bashrc

# 3. Uninstall Openclaw
npm uninstall -g openclaw

# 4. Delete directories
rm -rf ~/openclaw-logs
rm -rf ~/.npm-global

# 5. Reload bashrc
source ~/.bashrc
```

---

## Technical Details

### Script Architecture

```
install-openclaw-termux.sh
├── Parameter Parsing (parse arguments)
│   ├── --verbose, -v
│   ├── --dry-run, -d
│   ├── --uninstall, -u
│   └── --help, -h
├── Core Functions (core functions)
│   ├── check_deps()          # Check dependencies
│   ├── configure_npm()       # Configure NPM
│   ├── apply_patches()       # Apply patches
│   ├── setup_autostart()     # Configure autostart
│   ├── activate_wakelock()   # Activate wake lock
│   ├── start_service()       # Start service
│   └── uninstall_openclaw() # Uninstall function
├── Helper Functions (helper functions)
│   ├── log()                 # Log recording
│   └── run_cmd()             # Command execution
└── Main Execution (main execution)
    ├── Environment initialization
    ├── Interactive configuration
    └── Step execution
```

### Compatibility Patches Details

#### 1. Logger Patch

**Problem**: Openclaw defaults to using `/tmp/openclaw` as the log directory, but Termux's `/tmp` may not exist or be writable.

**Solution**:
```javascript
// Before replacement
/tmp/openclaw

// After replacement
$HOME/openclaw-logs
```

**Implementation**:
```bash
node -e "const fs = require('fs'); const file = '$LOGGER_FILE'; 
let c = fs.readFileSync(file, 'utf8'); 
c = c.replace(/\/tmp\/openclaw/g, process.env.HOME + '/openclaw-logs'); 
fs.writeFileSync(file, c);"
```

#### 2. Clipboard Patch

**Problem**: The `@mariozechner/clipboard` module depends on native C++ modules and fails to compile in Termux.

**Solution**: Replace the original clipboard module with a mock object.

**Implementation**:
```bash
node -e "const fs = require('fs'); const file = '$CLIP_FILE'; 
const mock = 'module.exports = { 
  availableFormats:()=>[], 
  getText:()=>\"\", 
  setText:()=>false, 
  // ... other methods
};'; 
fs.writeFileSync(file, mock);"
```

### Error Handling Mechanism

```bash
# Global error capture
trap 'echo -e "${RED}Error: Script execution failed, please check the above output${NC}"; exit 1' ERR

# Strict mode
set -e          # Exit immediately on error
set -o pipefail # Any command failure in pipeline is considered a failure

# Per-step error check
if [ $? -ne 0 ]; then
    log "Operation failed"
    echo -e "${RED}Error: Operation failed${NC}"
    exit 1
fi
```

### Log System

```bash
# Log directory structure
$HOME/openclaw-logs/
├── install.log    # Installation process log
└── runtime.log    # Runtime log (generated by Openclaw)

# Log format
YYYY-MM-DD HH:MM:SS [Log content]

# Log levels
- INFO: General information
- WARNING: Warning information
- ERROR: Error information
```

---

## FAQ

<details>
<summary><b>Q1: Why is Node.js ≥ 22 required?</b></summary>

Openclaw depends on the latest JavaScript features and native modules. Node.js 22 introduces the following key improvements:
- Better ES module support
- Improved V8 engine performance
- Native module ABI compatibility
- Enhanced security

The Node.js version installed by default in Termux may be lower, so the script will force check and prompt for an upgrade.
</details>

<details>
<summary><b>Q2: The script modifies ~/.bashrc, will it affect other configurations?</b></summary>

No. The script will automatically create a backup file `~/.bashrc.backup` before modification. All added configurations are included within clear markers:

```bash
# --- Openclaw Start ---
...
# --- OpenClaw End ---
```

When uninstalling, the script will automatically delete these configurations and optionally restore the original bashrc.
</details>

<details>
<summary><b>Q3: How to use the same script on multiple devices?</b></summary>

The script fully supports multi-device deployment, and each device's configuration (port, token) is independent:

1. Run the script separately on each device
2. Set different ports or tokens for each device
3. Use the same commands to manage the service

**Note**: If all devices are on the same local network, ensure using different ports to avoid conflicts.
</details>

<details>
<summary><b>Q4: Can I change the NPM mirror source?</b></summary>

Yes. The script defaults to using the Taobao mirror `https://registry.npmmirror.com`, you can manually modify:

```bash
# View current mirror
npm config get registry

# Change to other mirror (e.g., official source)
npm config set registry https://registry.npmjs.org

# Or use other domestic mirrors
# Huawei Cloud
npm config set registry https://mirrors.huaweicloud.com/repository/npm/
# Tencent Cloud
npm config set registry https://mirrors.cloud.tencent.com/npm/
```
</details>

<details>
<summary><b>Q5: How to automatically restart after service crash?</b></summary>

The current version uses tmux to keep the service running but will not automatically restart. You can use the following methods to achieve automatic restart:

**Method 1: Using loop script**
```bash
while true; do
  openclaw gateway --bind lan --port <port> --token <token>
  sleep 5
done
```

**Method 2: Using systemd (Termux:Boot)**
```bash
# Install Termux:Boot
pkg install termux-boot

# Create startup script
cat > ~/.termux/boot/openclaw.sh << EOF
#!/bin/bash
tmux new -d -s openclaw 'openclaw gateway --bind lan --port <port> --token <token>'
EOF
chmod +x ~/.termux/boot/openclaw.sh
```
</details>

<details>
<summary><b>Q6: How to view Openclaw's version and configuration?</b></summary>

```bash
# View Openclaw version
openclaw --version

# View Gateway configuration
openclaw gateway --help

# View currently running services
openclaw status
```
</details>

<details>
<summary><b>Q7: Service runs normally in Termux foreground but stops in background?</b></summary>

This is caused by Android's battery optimization mechanism. Solution:

1. **Disable battery optimization**:
   - Settings → Apps → Termux → Battery → Cancel battery optimization

2. **Activate wake lock** (automatically executed by script):
   ```bash
   termux-wake-lock
   ```

3. **Add to whitelist**:
   - Some phones need to add Termux to the background running whitelist in system settings

4. **Use Termux:Boot**:
   ```bash
   pkg install termux-boot
   ```
</details>

<details>
<summary><b>Q8: How to backup and migrate Openclaw configuration?</b></summary>

```bash
# Backup configuration
mkdir -p ~/openclaw-backup
cp ~/.bashrc ~/openclaw-backup/
cp -r ~/.npm-global ~/openclaw-backup/

# Migrate to new device
# 1. Transfer backup directory to new device
# 2. Restore configuration
cp ~/openclaw-backup/.bashrc ~/.bashrc
cp -r ~/openclaw-backup/.npm-global ~/.npm-global

# 3. Re-run script
source install-openclaw-termux.sh
```
</details>

---

## Contributing

Contributions, bug reports, and suggestions are welcome!

### Reporting Issues

Before submitting an issue, please confirm:

1. ✅ Have read the "Troubleshooting" section of this document
2. ✅ Provide detailed error information and reproduction steps
3. ✅ Attach relevant logs (`$HOME/openclaw-logs/runtime.log`)
4. ✅ Describe your system environment (Termux version, Android version, Node.js version, etc.)

### Submitting Code

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Code Standards

- Follow ShellCheck best practices
- Add necessary comments and documentation
- Ensure it runs in a standard Termux environment
- Test that your changes don't break existing functionality

---

## Changelog

### v2.0 (Current Version)

- ✨ Add command-line options support (--verbose, --dry-run, --uninstall)
- ✨ Improve error handling and log system
- ✨ Optimize dependency check and installation process
- 🐛 Fix Logger path patch verification failure issue
- 🐛 Fix clipboard module patch application failure issue
- 📝 Improve documentation and help information

### v1.0 (Initial Version)

- ✨ Basic one-click installation function
- ✨ Dependency check and installation
- ✨ Android compatibility patches
- ✨ tmux background running support
- ✨ Basic alias commands

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details

---

## Acknowledgments

- [Openclaw](https://github.com/openclaw/openclaw) - Core project
- [Termux](https://termux.com/) - Powerful Android terminal emulator
- Google Gemini
- All contributors and users for their feedback and support

---

## Contact

- **Project Homepage**: [GitHub Repository](https://github.com/hillerliao/install-openclaw-on-termux)
- **Issue Reporting**: [GitHub Issues](https://github.com/hillerliao/install-openclaw-on-termux/issues)
- **Email**: riao@zhihai.me
- **WeChat Group**:

    ![OpenClaw-Termux-WeChat-Group-QRCode](./sources/OpenClaw-Termux-Group.png)

---

## Sponsorship

If you find this project helpful, welcome to support in the following ways:

- ⭐ Give the project a Star
- 🐛 Report issues or make suggestions
- 💡 Share your experience
- 💰 Sponsor project development (optional)

---

<div align="center">

**If this project helps you, please give it a ⭐️ Star**

Made with ❤️ by the Openclaw Community

</div>
