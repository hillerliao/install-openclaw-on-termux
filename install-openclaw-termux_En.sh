#!/bin/bash
# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================
#
# Usage: curl -sL https://s.zhihai.me/openclaw_en > openclaw-install.sh && source openclaw-install.sh [options]
#
# Options:
#   --help, -h       Show help information
#   --verbose, -v    Enable verbose output (shows command execution details)
#   --dry-run, -d    Dry run mode (simulate execution without making changes)
#   --uninstall, -u  Uninstall Openclaw and clean up configurations
#   --update, -U     Force update Openclaw to latest version without prompting
#
# Examples:
#   curl -sL https://s.zhihai.me/openclaw_en > openclaw-install.sh && source openclaw-install.sh
#   curl -sL https://s.zhihai.me/openclaw_en > openclaw-install.sh && source openclaw-install.sh --verbose
#   curl -sL https://s.zhihai.me/openclaw_en > openclaw-install.sh && source openclaw-install.sh --dry-run
#   curl -sL https://s.zhihai.me/openclaw_en > openclaw-install.sh && source openclaw-install.sh --uninstall
#   curl -sL https://s.zhihai.me/openclaw_en > openclaw-install.sh && source openclaw-install.sh --update
#
# Note: For direct local execution, use: source install-openclaw-termux.sh [options]
#
# ==========================================

# Note: This script is recommended to be executed via 'source' so that aliases and environment variables take effect immediately
# Detect execution method, prompt when not using 'source' mode
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _NEED_PROMPT=1
fi
trap 'if [ "$_NEED_PROMPT" = "1" ]; then echo ""; echo "Warning: Please run the following command to make aliases (ocr-restart, ockill-force stop, oclog-view logs) effective:"; echo "   source ~/.bashrc"; fi' EXIT

# Parse command line options
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
            echo "Usage: source $0 [options]"
            echo "Options:"
            echo "  --verbose, -v    Enable verbose output"
            echo "  --dry-run, -d    Dry run mode, simulate without executing actual commands"
            echo "  --uninstall, -u  Uninstall Openclaw and related configurations"
            echo "  --update, -U     Force update to latest version"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "Note: It is recommended to use 'source' to execute, so that aliases (ocr-restart, ockill-force stop, oclog-view logs) take effect immediately"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help to view help"
            exit 1
            ;;
    esac
done

trap 'echo -e "${RED}Error: Script execution failed, please check the output above${NC}"' ERR

# ==========================================
# Openclaw Termux Deployment Script v2.0
# ==========================================

# Color definitions
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
WHITE_ON_BLUE='\033[44;37;1m'
NC='\033[0m'

# Check if terminal supports colors
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    : # Supported, keep colors
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

# Define common path variables
BASHRC="$HOME/.bashrc"
NPM_GLOBAL="$HOME/.npm-global"
NPM_BIN="$NPM_GLOBAL/bin"
LOG_DIR="$HOME/openclaw-logs"
LOG_FILE="$LOG_DIR/install.log"

# Create log directory (prevent log function from erroring when directory doesn't exist)
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Command execution function (supports dry-run)
run_cmd() {
    if [ $VERBOSE -eq 1 ]; then
        echo "[VERBOSE] Executing: $@"
    fi
    log "Executing command: $@"
    if [ $DRY_RUN -eq 1 ]; then
        echo "[DRY-RUN] Skipping: $@"
        return 0
    else
        "$@"
    fi
}

# Function definitions

apply_koffi_stub() {
    # Apply koffi stub for Termux compatibility (android-arm64)
    # koffi is only used by pi-tui for Windows VT input, which never executes on Android
    log "Applying koffi stub"
    echo -e "${YELLOW}[2.5/6] Applying koffi compatibility fix...${NC}"
    
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
        log "koffi stub applied successfully"
        echo -e "${GREEN}koffi stub applied successfully${NC}"
    else
        log "koffi directory not found, skipping stub"
    fi
}

check_deps() {
    # Check and install basic dependencies
    log "Starting basic environment check"
    echo -e "${YELLOW}[1/6] Checking basic runtime environment...${NC}"

    # Check if pkg update is needed
    UPDATE_FLAG="$HOME/.pkg_last_update"
    if [ ! -f "$UPDATE_FLAG" ] || [ $(($(date +%s) - $(stat -c %Y "$UPDATE_FLAG" 2>/dev/null || echo 0))) -gt 86400 ]; then
        log "Executing pkg update"
        echo -e "${YELLOW}Updating package list...${NC}"
        run_cmd pkg update -y
        if [ $? -ne 0 ]; then
            log "pkg update failed"
            echo -e "${RED}Error: pkg update failed${NC}"
            exit 1
        fi
        run_cmd touch "$UPDATE_FLAG"
        log "pkg update completed"
    else
        log "Skipping pkg update (already updated)"
        echo -e "${GREEN}Package list is up to date${NC}"
    fi

    # Define required basic packages (includes build tools for native module compilation)
    DEPS=("nodejs-lts" "git" "openssh" "tmux" "termux-api" "termux-tools" "cmake" "python" "golang" "which" "clang" "ninja" "pkg-config" "build-essential")
    MISSING_DEPS=()

    for dep in "${DEPS[@]}"; do
        cmd=$dep
        if [ "$dep" = "nodejs-lts" ]; then cmd="node"; fi
        if ! command -v "$cmd" &> /dev/null; then
            MISSING_DEPS+=("$dep")
        fi
    done

    # Install missing dependencies (including nodejs) first, then check version
    if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
        log "Missing dependencies: ${MISSING_DEPS[*]}"
        echo -e "${YELLOW}Checking for potentially missing components: ${MISSING_DEPS[*]}${NC}"
        run_cmd pkg upgrade -y
        if [ $? -ne 0 ]; then
            log "pkg upgrade failed"
            echo -e "${RED}Error: pkg upgrade failed${NC}"
            exit 1
        fi
        run_cmd pkg install ${MISSING_DEPS[*]} -y
        if [ $? -ne 0 ]; then
            log "Dependency installation failed"
            echo -e "${RED}Error: Dependency installation failed${NC}"
            exit 1
        fi
        log "Dependencies installed successfully"
    else
        log "All dependencies are installed"
        echo -e "${GREEN}✅ Basic environment is ready${NC}"
    fi

    # After dependencies are installed, display version info
    log "Node.js version: $(node --version 2>/dev/null || echo 'unknown')"
    echo -e "${BLUE}Node.js version: $(node -v)${NC}"
    echo -e "${BLUE}NPM version: $(npm -v)${NC}" 

    # Check Node.js version (must be 22 or higher)
    NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
    if [ -z "$NODE_VERSION" ] || [ "$NODE_VERSION" -lt 22 ]; then
        log "Node.js version check failed: $NODE_VERSION"
        echo -e "${RED}Error: Node.js version must be 22 or higher, current version: $(node --version 2>/dev/null || echo 'unknown')${NC}"
        exit 1
    fi
    
    # Warning: If using Node.js 25 (non-LTS), warn about potential compatibility issues and offer downgrade option
    if [ "$NODE_VERSION" -eq 25 ]; then
        log "Warning: Node.js 25 (non-LTS version) detected"
        echo -e "${YELLOW}⚠️  Warning: You are using Node.js 25 (Current version), which may encounter native module compatibility issues${NC}"
        echo -e "${YELLOW}    It is recommended to downgrade to Node.js 24 LTS for better stability${NC}"
        echo ""
        read -p "Downgrade to Node.js 24 LTS? (y/n) [default: y]: " DOWNGRADE_CHOICE
        DOWNGRADE_CHOICE=${DOWNGRADE_CHOICE:-y}
        
        if [ "$DOWNGRADE_CHOICE" = "y" ] || [ "$DOWNGRADE_CHOICE" = "Y" ]; then
            log "Starting Node.js downgrade to LTS version"
            echo -e "${YELLOW}Downgrading Node.js to 24 LTS...${NC}"
            
            # Uninstall current Node.js version first
            run_cmd pkg uninstall nodejs -y
            if [ $? -ne 0 ]; then
                log "Node.js uninstall failed"
                echo -e "${RED}Error: Node.js uninstall failed${NC}"
                exit 1
            fi
            
            # Install Node.js LTS version
            run_cmd pkg install nodejs-lts -y
            if [ $? -ne 0 ]; then
                log "Node.js LTS installation failed"
                echo -e "${RED}Error: Node.js LTS installation failed${NC}"
                exit 1
            fi
            
            # Re-get Node.js version
            NODE_VERSION=$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)
            echo -e "${GREEN}✅ Node.js downgraded to $(node --version)${NC}"
            log "Node.js downgrade completed: $(node --version)"
        else
            log "User chose to continue with Node.js 25"
            echo -e "${YELLOW}Continuing installation, but may encounter compatibility issues${NC}"
            read -p "Continue? (y/n) [default: n]: " CONTINUE_INSTALL
            CONTINUE_INSTALL=${CONTINUE_INSTALL:-n}
            if [ "$CONTINUE_INSTALL" != "y" ] && [ "$CONTINUE_INSTALL" != "Y" ]; then
                log "User chose to exit installation"
                echo -e "${YELLOW}Installation cancelled${NC}"
                exit 0
            fi
        fi
    fi
    
    log "Node.js version check passed: $NODE_VERSION"

    touch "$BASHRC" 2>/dev/null

    log "Setting NPM mirror"
    npm config set registry https://registry.npmmirror.com
    if [ $? -ne 0 ]; then
        log "NPM mirror setup failed"
        echo -e "${RED}Error: NPM mirror setup failed${NC}"
        exit 1
    fi
}

configure_npm() {
    # Configure NPM environment and install Openclaw
    log "Starting NPM configuration"
    echo -e "\n${YELLOW}[2/6] Configuring Openclaw...${NC}"

    # Configure NPM global environment
    mkdir -p "$NPM_GLOBAL"
    npm config set prefix "$NPM_GLOBAL"
    if [ $? -ne 0 ]; then
        log "NPM prefix setup failed"
        echo -e "${RED}Error: NPM prefix setup failed${NC}"
        exit 1
    fi
    # Check if correct PATH setting already exists (avoid duplicate entries)
    if ! grep -q "export PATH=$NPM_BIN:" "$BASHRC" 2>/dev/null; then
        echo "export PATH=$NPM_BIN:\$PATH" >> "$BASHRC"
    fi
    export PATH="$NPM_BIN:$PATH"

    # Create necessary directories before installation (Termux compatibility handling)
    log "Creating Termux compatibility directories"
    mkdir -p "$LOG_DIR" "$HOME/tmp"
    if [ $? -ne 0 ]; then
        log "Directory creation failed"
        echo -e "${RED}Error: Directory creation failed${NC}"
        exit 1
    fi

    # Set temporary directory (required for node-gyp compilation)
    export TMPDIR="$HOME/tmp"

    # Configure git to use HTTPS instead of SSH (resolves Termux SSH connection issues)
    log "Configuring git HTTPS"
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" 2>/dev/null || true
    git config --global --add url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true
    echo -e "${GREEN}✓ git HTTPS configuration completed${NC}"

    # Create GYP configuration (prevents node-gyp from looking for Android NDK)
    log "Configuring GYP environment"
    mkdir -p "$HOME/.gyp"
    echo "{'variables':{'android_ndk_path':''}}" > "$HOME/.gyp/include.gypi"
    echo -e "${GREEN}✓ GYP configuration completed${NC}"

    # Check and install/update Openclaw
    TARGET_VERSION="latest"  # Specify installation version
    INSTALLED_VERSION=""
    LATEST_VERSION=""
    NEED_UPDATE=0

    log "Checking Openclaw installation status"
    if [ -f "$NPM_BIN/openclaw" ]; then
        log "Openclaw is installed, checking version"
        echo -e "${BLUE}Checking Openclaw version...${NC}"
        INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
        if [ -z "$INSTALLED_VERSION" ]; then
            log "Version extraction failed, trying fallback method"
            INSTALLED_VERSION=$(npm view openclaw version 2>/dev/null || echo "unknown")
        fi
        echo -e "${BLUE}Current version: $INSTALLED_VERSION${NC}"

        # Get latest version
        log "Getting latest version info"
        echo -e "${BLUE}Fetching latest version info from npm...${NC}"
        LATEST_VERSION=$(npm view openclaw version 2>/dev/null || echo "")

        if [ -z "$LATEST_VERSION" ]; then
            log "Unable to get latest version info"
            echo -e "${YELLOW}⚠️  Unable to get latest version info (possibly network issue), keeping current version${NC}"
        else
            echo -e "${BLUE}Latest version: $LATEST_VERSION${NC}"

            # Simple version comparison
            if [ "$INSTALLED_VERSION" != "$LATEST_VERSION" ]; then
                log "New version found: $LATEST_VERSION (current: $INSTALLED_VERSION)"
                echo -e "${YELLOW}🔔 New version found: $LATEST_VERSION (current: $INSTALLED_VERSION)${NC}"

                if [ $FORCE_UPDATE -eq 1 ]; then
                    log "Force update mode, updating directly"
                    echo -e "${YELLOW}Updating Openclaw...${NC}"
                    # Use --ignore-scripts to skip native module compilation (koffi/clipboard cannot compile on Termux)
                    run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw@$TARGET_VERSION --ignore-scripts
                    if [ $? -ne 0 ]; then
                        log "Openclaw update failed"
                        echo -e "${RED}Error: Openclaw update failed${NC}"
                        exit 1
                    fi
                    log "Openclaw update completed"
                    INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
                    echo -e "${GREEN}✅ Openclaw updated to $INSTALLED_VERSION${NC}"
                else
                    read -p "Update to new version? (y/n) [default: y]: " UPDATE_CHOICE
                    UPDATE_CHOICE=${UPDATE_CHOICE:-y}

                    if [ "$UPDATE_CHOICE" = "y" ] || [ "$UPDATE_CHOICE" = "Y" ]; then
                        log "Starting Openclaw update"
                        echo -e "${YELLOW}Updating Openclaw...${NC}"
                        # Use --ignore-scripts to skip native module compilation (koffi/clipboard cannot compile on Termux)
                        run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw@$TARGET_VERSION --ignore-scripts
                        if [ $? -ne 0 ]; then
                            log "Openclaw update failed"
                            echo -e "${RED}Error: Openclaw update failed${NC}"
                            exit 1
                        fi
                        log "Openclaw update completed"
                        INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
                        echo -e "${GREEN}✅ Openclaw updated to $INSTALLED_VERSION${NC}"
                    else
                        log "User chose to skip update"
                        echo -e "${YELLOW}Skipping update, using current version${NC}"
                    fi
                fi
            else
                log "Version is already up to date"
                echo -e "${GREEN}✅ Openclaw is already the latest version $INSTALLED_VERSION${NC}"
            fi
        fi
    else
        log "Starting Openclaw installation"
        echo -e "${YELLOW}Installing Openclaw $TARGET_VERSION...${NC}"
        # Use --ignore-scripts to skip native module compilation (koffi/clipboard cannot compile on Termux)
        run_cmd env NODE_LLAMA_CPP_SKIP_DOWNLOAD=true npm i -g openclaw@$TARGET_VERSION --ignore-scripts
        if [ $? -ne 0 ]; then
            log "Openclaw installation failed"
            echo -e "${RED}Error: Openclaw installation failed${NC}"
            exit 1
        fi
        log "Openclaw installation completed"
        INSTALLED_VERSION=$(npm list -g openclaw --depth=0 2>/dev/null | grep -oE 'openclaw@[0-9]+\.[0-9]+\.[0-9]+' | cut -d@ -f2)
        if [ -z "$INSTALLED_VERSION" ]; then
            INSTALLED_VERSION=$(npm view openclaw version 2>/dev/null || echo "unknown")
        fi
        echo -e "${GREEN}✅ Openclaw installed (version: $INSTALLED_VERSION)${NC}"
    fi

    BASE_DIR="$NPM_GLOBAL/lib/node_modules/openclaw"

    # Verify if dist directory exists
    if [ ! -d "$BASE_DIR/dist" ]; then
        log "dist directory missing, attempting to build..."
        echo -e "${YELLOW}⚠️  dist directory missing, attempting to build...${NC}"
        cd "$BASE_DIR"
        # Try multiple build methods
        if [ -f "tsconfig.json" ]; then
            npx tsc --skipLibCheck 2>/dev/null || true
        fi
        npm run build 2>/dev/null || true
        # Verify again
        if [ ! -d "$BASE_DIR/dist" ]; then
            log "dist directory build failed"
            echo -e "${RED}Error: dist directory build failed, Openclaw may not run properly${NC}"
            echo -e "${YELLOW}Please check for compilation errors or try building manually${NC}"
            exit 1
        fi
        log "dist directory built successfully"
        echo -e "${GREEN}✓ dist directory built successfully${NC}"
    fi

    # Create openclaw wrapper script (resolves ESM bin path resolution issues)
    # Original bin file uses ESM dynamic import, symlink method cannot correctly resolve module paths
    # Use shell script wrapper to directly call node to execute entry.js
    log "Creating openclaw wrapper script"
    if [ -d "$BASE_DIR/dist" ] && [ -f "$BASE_DIR/dist/entry.js" ]; then
        cat > "$NPM_BIN/openclaw" << WRAPPER
#!/data/data/com.termux/files/usr/bin/sh
exec node $BASE_DIR/dist/entry.js "\$@"
WRAPPER
        chmod +x "$NPM_BIN/openclaw"
        echo -e "${GREEN}✓ openclaw wrapper script created successfully${NC}"
    fi

    # Apply koffi stub (Termux compatibility fix)
    apply_koffi_stub
}

apply_patches() {
    # Apply Android compatibility patches
    log "Starting patch application"
    echo -e "${YELLOW}[3/6] Applying Android compatibility patches...${NC}"

    # Check if BASE_DIR exists
    if [ ! -d "$BASE_DIR" ]; then
        log "BASE_DIR does not exist: $BASE_DIR"
        echo -e "${RED}Error: Openclaw installation directory does not exist${NC}"
        exit 1
    fi

    # Fix all files containing /tmp/openclaw path
    log "Searching and fixing all hardcoded /tmp/openclaw paths"
    
    # Search for all files containing /tmp/openclaw in the openclaw directory
    cd "$BASE_DIR" || { log "Cannot enter $BASE_DIR"; exit 1; }
    FILES_WITH_TMP=$(grep -rl "/tmp/openclaw" dist/ 2>/dev/null || true)
    
    if [ -n "$FILES_WITH_TMP" ]; then
        log "Found files needing fixes"
        while IFS= read -r file; do
            log "Fixing file: $file"
            node -e "const fs = require('fs'); const file = '$BASE_DIR/$file'; let c = fs.readFileSync(file, 'utf8'); c = c.replace(/\/tmp\/openclaw/g, process.env.HOME + '/openclaw-logs'); fs.writeFileSync(file, c);"
        done <<< "$FILES_WITH_TMP"
        log "All files fixed successfully"
    else
        log "No files found needing fixes"
    fi
    
    # Verify if patches were applied
    REMAINING=$(grep -r "/tmp/openclaw" dist/ 2>/dev/null || true)
    if [ -n "$REMAINING" ]; then
        log "Patch verification failed, some files still contain /tmp/openclaw"
        echo -e "${RED}Warning: Some files still contain /tmp/openclaw path${NC}"
        echo -e "${YELLOW}Affected files:${NC}"
        echo "$REMAINING"
    else
        log "Patch verification successful, all paths replaced"
        echo -e "${GREEN}✓ All /tmp/openclaw paths replaced with $HOME/openclaw-logs${NC}"
    fi

    # Fix hardcoded /bin/npm path (in Termux, npm is located at $PREFIX/bin/npm)
    log "Searching and fixing hardcoded /bin/npm paths"
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
            log "Found files containing /bin/npm, replacing with $REAL_NPM"
            while IFS= read -r file; do
                log "Fixing file: $file"
                sed -i "s|/bin/npm|${REAL_NPM}|g" "$BASE_DIR/$file"
            done <<< "$FILES_WITH_NPM"
            echo -e "${GREEN}✓ /bin/npm path replaced with $REAL_NPM${NC}"
        else
            log "No files found containing /bin/npm"
        fi
    else
        log "npm path does not need fixing"
    fi

    # Fix clipboard
    CLIP_FILE="$BASE_DIR/node_modules/@mariozechner/clipboard/index.js"
    if [ -f "$CLIP_FILE" ]; then
        log "Applying clipboard patch"
        node -e "const fs = require('fs'); const file = '$CLIP_FILE'; const mock = 'module.exports = { availableFormats:()=>[], getText:()=>\"\", setText:()=>false, hasText:()=>false, getImageBinary:()=>null, getImageBase64:()=>null, setImageBinary:()=>false, setImageBase64:()=>false, hasImage:()=>false, getHtml:()=>\"\", setHtml:()=>false, hasHtml:()=>false, getRtf:()=>\"\", setRtf:()=>false, hasRtf:()=>false, clear:()=>{}, watch:()=>({stop:()=>{}}), callThreadsafeFunction:()=>{} };'; fs.writeFileSync(file, mock);"
        if [ $? -ne 0 ]; then
            log "Clipboard patch application failed"
            echo -e "${RED}Error: Clipboard patch application failed${NC}"
            exit 1
        fi
        # Verify if patch was applied
        if ! grep -q "availableFormats" "$CLIP_FILE"; then
            log "Clipboard patch verification failed"
            echo -e "${RED}Error: Clipboard patch was not applied correctly, please check file content${NC}"
            exit 1
        fi
        log "Clipboard patch applied successfully"
    fi

    # Fix openclaw executable shebang (Termux compatibility)
    OPENCLAW_BIN="$NPM_BIN/openclaw"
    if [ -f "$OPENCLAW_BIN" ]; then
        log "Checking and fixing openclaw executable shebang"
        # Only fix when /usr/bin/env doesn't exist (i.e., Termux environment)
        if [ ! -x "/usr/bin/env" ] && head -n1 "$OPENCLAW_BIN" | grep -q "^#!/usr/bin/env"; then
            # Use PREFIX environment variable to get Termux's actual prefix path
            TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
            # Confirm target env exists and is executable
            if [ -x "${TERMUX_PREFIX}/bin/env" ]; then
                sed -i "1s|#!/usr/bin/env|#!${TERMUX_PREFIX}/bin/env|" "$OPENCLAW_BIN"
                log "openclaw shebang fixed"
                echo -e "${GREEN}✓ openclaw shebang fixed to Termux compatible path${NC}"
            else
                log "Warning: Termux env path does not exist"
                echo -e "${YELLOW}⚠️  Termux env path does not exist, skipping shebang fix${NC}"
            fi
        else
            log "openclaw shebang does not need fixing"
        fi
    fi
}

setup_autostart() {
    # Configure aliases and optional autostart
    log "Configuring environment variables and aliases"
    # Backup original ~/.bashrc file
    run_cmd cp "$BASHRC" "$BASHRC.backup"
    # Clean up old configuration blocks (compatible with old version case-insensitive markers)
    run_cmd sed -i '/# --- [Oo]pen[Cc]law Start ---/,/# --- [Oo]pen[Cc]law End ---/d' "$BASHRC"
    if [ $? -ne 0 ]; then
        log "bashrc modification failed"
        echo -e "${RED}Error: bashrc modification failed${NC}"
        exit 1
    fi

    # Build autostart section (only include sshd/wake-lock when user chooses autostart)
    AUTOSTART_BLOCK=""
    if [ "$AUTO_START" == "y" ]; then
        log "Configuring autostart"
        AUTOSTART_BLOCK="sshd 2>/dev/null
termux-wake-lock 2>/dev/null"
    else
        log "Skipping autostart (only writing aliases and environment variables)"
    fi

    # Write configuration block (functions are always written, $NPM_BIN expands to actual path at write time)
    cat >> "$BASHRC" <<EOT
# --- OpenClaw Start ---
# WARNING: This section contains your access token - keep ~/.bashrc secure
export TERMUX_VERSION=1
export TMPDIR=\$HOME/tmp
export OPENCLAW_GATEWAY_TOKEN=$TOKEN
export PATH=$NPM_BIN:\$PATH
${AUTOSTART_BLOCK}

# OpenClaw color definitions
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# OpenClaw service management functions
ocr() {
    echo -e "\${YELLOW}Starting/restarting OpenClaw service...\${NC}"
    pkill -9 -f 'openclaw' 2>/dev/null
    tmux kill-session -t openclaw 2>/dev/null
    sleep 1
    tmux new -d -s openclaw
    sleep 1
    tmux send-keys -t openclaw "export PATH=$NPM_BIN:\$PATH TMPDIR=\$HOME/tmp OPENCLAW_GATEWAY_TOKEN=\$OPENCLAW_GATEWAY_TOKEN; openclaw gateway --bind loopback --port $PORT --token \\\$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured" C-m
    sleep 2
    if tmux has-session -t openclaw 2>/dev/null; then
        echo ""
        echo -e "\${GREEN}✅ OpenClaw service started\${NC}"
        echo ""
        echo -e "\${CYAN}📖 Usage:\${NC}"
        echo "   1. Open in phone browser:: http://localhost:$PORT/?token=\$OPENCLAW_GATEWAY_TOKEN"
        echo "   2. Or run command: openclaw tui"
        echo "   3. Or use Telegram bot (if configured)"
        echo ""
        echo -e "\${BLUE}💡 oclog to view logs | ockill to stop service\${NC}"
    else
        echo -e "\${RED}❌ Service failed to start, please check logs (openclaw logs)\${NC}"
    fi
}

oclog() {
    if tmux has-session -t openclaw 2>/dev/null; then
        tmux attach -t openclaw
    else
        echo -e "\${YELLOW}⚠️  OpenClaw service not running, use ocr to start\${NC}"
    fi
}

ockill() {
    echo -e "\${YELLOW}Stopping OpenClaw service...\${NC}"
    pkill -9 -f "openclaw" 2>/dev/null
    tmux kill-session -t openclaw 2>/dev/null
    sleep 1
    if ! tmux has-session -t openclaw 2>/dev/null && ! pgrep -f "openclaw" > /dev/null; then
        echo -e "\${GREEN}✅ OpenClaw service stopped\${NC}"
    else
        echo -e "\${RED}❌ Failed to stop service, please check manually\${NC}"
    fi
}
# --- OpenClaw End ---
EOT

    source "$BASHRC"
    if [ $? -ne 0 ]; then
        log "bashrc loading warning"
        echo -e "${YELLOW}Warning: bashrc loading failed, aliases may be affected${NC}"
    fi
    log "Aliases and environment variables configuration completed"
}

activate_wakelock() {
    # Activate wake lock to prevent sleep
    log "Activating wake lock"
    echo -e "${YELLOW}[4/6] Activating wake lock...${NC}"
    termux-wake-lock 2>/dev/null
    if [ $? -eq 0 ]; then
        log "Wake lock activated successfully"
        echo -e "${GREEN}✅ Wake-lock activated${NC}"
    else
        log "Wake lock activation failed"
        echo -e "${YELLOW}⚠️  Wake-lock activation failed, termux-api may not be installed correctly${NC}"
    fi
}

start_service() {
    log "Starting service"
    echo -e "${YELLOW}[5/6] Starting service...${NC}"

    # Check if there's an instance running
    RUNNING_PROCESS=$(pgrep -f "openclaw gateway" 2>/dev/null || true)
    HAS_TMUX_SESSION=$(tmux has-session -t openclaw 2>/dev/null && echo "yes" || echo "no")

    if [ -n "$RUNNING_PROCESS" ] || [ "$HAS_TMUX_SESSION" = "yes" ]; then
        log "Found existing Openclaw instance running"
        echo -e "${YELLOW}⚠️  Detected Openclaw instance already running${NC}"
        echo -e "${BLUE}Running process: $RUNNING_PROCESS${NC}"
        read -p "Stop old instance and start new one? (y/n) [default: y]: " RESTART_CHOICE
        RESTART_CHOICE=${RESTART_CHOICE:-y}

        if [ "$RESTART_CHOICE" = "y" ] || [ "$RESTART_CHOICE" = "Y" ]; then
            log "Stopping old instance"
            echo -e "${YELLOW}Stopping old instance...${NC}"
            # Only stop openclaw related processes, don't kill all node processes
            pkill -9 -f "openclaw" 2>/dev/null || true
            tmux kill-session -t openclaw 2>/dev/null || true
            sleep 1
        else
            log "User chose not to restart"
            echo -e "${GREEN}Skipping startup, keeping current instance running${NC}"
            return 0
        fi
    fi

    # 2. Ensure directories exist
    mkdir -p "$HOME/tmp"
    export TMPDIR="$HOME/tmp"

    # 3. Create session and capture possible errors
    # First start a shell, then execute commands in the shell for easier observation
    tmux new -d -s openclaw
    sleep 1
    
    # Redirect output to a temporary file, so we can see errors if tmux crashes
    tmux send-keys -t openclaw "export PATH=$NPM_BIN:\$PATH TMPDIR=$HOME/tmp OPENCLAW_GATEWAY_TOKEN=\$OPENCLAW_GATEWAY_TOKEN; openclaw gateway --bind loopback --port $PORT --token \\\$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured 2>&1 | tee $LOG_DIR/runtime.log" C-m
    
    log "Service command sent"
    echo ""
    
    # 4. Real-time verification
    sleep 2
    if tmux has-session -t openclaw 2>/dev/null; then
        echo -e "${GREEN}[6/6] ✅ tmux session established, Gateway service started!${NC}"
    else
        echo -e "${RED}❌ Error: tmux session crashed immediately after startup.${NC}"
        echo -e "Please check error log: ${YELLOW}cat $LOG_DIR/runtime.log${NC}"
    fi
}

uninstall_openclaw() {
    # Uninstall Openclaw and clean up configurations
    log "Starting Openclaw uninstallation"
    echo -e "${YELLOW}Starting Openclaw uninstallation...${NC}"

    # Stop service
    echo -e "${YELLOW}Stopping service...${NC}"
    run_cmd pkill -9 -f "openclaw" 2>/dev/null || true
    run_cmd tmux kill-session -t openclaw 2>/dev/null || true
    log "Service stopped"

    # Delete aliases and configurations
    echo -e "${YELLOW}Deleting aliases and configurations...${NC}"
    # Use fixed text matching to avoid regex issues
    if grep -q "# --- OpenClaw Start ---" "$BASHRC" 2>/dev/null; then
        sed -i '/# --- OpenClaw Start ---/,/# --- OpenClaw End ---/d' "$BASHRC"
        log "Deleted OpenClaw configuration block"
    else
        log "OpenClaw configuration block not found"
    fi
    # Delete possible leftover PATH configuration
    sed -i '/export PATH=.*\.npm-global\/bin/d' "$BASHRC" 2>/dev/null || true
    log "Aliases and configurations deleted"

    # Restore backed up bashrc
    if [ -f "$BASHRC.backup" ]; then
        echo -e "${YELLOW}Restoring original ~/.bashrc...${NC}"
        run_cmd cp "$BASHRC.backup" "$BASHRC"
        run_cmd rm "$BASHRC.backup"
        log "bashrc restored"
    fi

    # Uninstall npm package
    echo -e "${YELLOW}Uninstalling Openclaw package...${NC}"
    run_cmd npm uninstall -g openclaw 2>/dev/null || true
    log "Openclaw package uninstalled"

    # Delete update flag
    run_cmd rm -f "$HOME/.pkg_last_update" 2>/dev/null || true

    # Backup and delete openclaw.json (before deleting log directory)
    if [ -f "$HOME/.openclaw/openclaw.json" ]; then
        echo -e "${YELLOW}Backing up openclaw.json...${NC}"
        run_cmd cp "$HOME/.openclaw/openclaw.json" "$HOME/.openclaw/openclaw.json.$(date +%Y%m%d_%H%M%S).bak"
        log "Backed up openclaw.json"
        run_cmd rm -f "$HOME/.openclaw/openclaw.json"
        log "Deleted openclaw.json"
    fi

    # Log completion (before deleting log directory)
    log "Uninstallation completed"

    # Finally delete log and npm global directories
    echo -e "${YELLOW}Deleting log directory and npm global directory...${NC}"
    run_cmd rm -rf "$LOG_DIR" 2>/dev/null || true
    run_cmd rm -rf "$NPM_GLOBAL" 2>/dev/null || true

    echo -e "${GREEN}Uninstallation completed!${NC}"
}

# Main script

# Uninstall mode executes directly
if [ $UNINSTALL -eq 1 ]; then
    uninstall_openclaw
    # In source mode, return only exits the script, exit would exit the entire shell
    [[ "${BASH_SOURCE[0]}" == "${0}" ]] && exit 0 || return 0
fi

clear
if [ $DRY_RUN -eq 1 ]; then
    echo -e "${YELLOW}🔍 Dry run mode: no actual commands will be executed${NC}"
fi
if [ $VERBOSE -eq 1 ]; then
    echo -e "${BLUE}Verbose output mode enabled${NC}"
fi
echo -e "${BLUE}=========================================="
echo -e "   🦞 Openclaw Termux Deployment Tool"
echo -e "==========================================${NC}"

# --- Interactive configuration ---
read -p "Enter Gateway port number [default: 18789]: " INPUT_PORT
if [ -z "$INPUT_PORT" ]; then
    echo -e "${GREEN}✓ Using default port: 18789${NC}"
    PORT=18789
else
    # Validate if port number is numeric
    if ! [[ "$INPUT_PORT" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Port number must be numeric, using default 18789${NC}"
        PORT=18789
    else
        PORT=$INPUT_PORT
        echo -e "${GREEN}✓ Using port: $PORT${NC}"
    fi
fi

# Check if Token already exists
if [ -n "$OPENCLAW_GATEWAY_TOKEN" ]; then
    echo -e "${GREEN}Detected existing Token: ${OPENCLAW_GATEWAY_TOKEN:0:8}...${NC}"
    read -p "Use existing Token? (y/n) [default: y]: " USE_EXISTING
    USE_EXISTING=${USE_EXISTING:-y}
    if [ "$USE_EXISTING" = "y" ] || [ "$USE_EXISTING" = "Y" ]; then
        TOKEN="$OPENCLAW_GATEWAY_TOKEN"
        echo -e "${GREEN}✓ Using existing Token${NC}"
    else
        read -p "Enter custom Token (OPENCLAW_GATEWAY_TOKEN for secure access, strong password recommended) [leave empty for random generation]: " TOKEN
        if [ -z "$TOKEN" ]; then
            RANDOM_PART=$(date +%s | md5sum | cut -c 1-8)
            TOKEN="token$RANDOM_PART"
            echo -e "${GREEN}Generated random Token: $TOKEN${NC}"
        fi
    fi
else
    read -p "Enter custom Token (for secure access, strong password recommended) [leave empty for random generation]: " TOKEN
    if [ -z "$TOKEN" ]; then
        RANDOM_PART=$(date +%s | md5sum | cut -c 1-8)
        TOKEN="token$RANDOM_PART"
        echo -e "${GREEN}Generated random Token: $TOKEN${NC}"
    fi
fi

read -p "Enable autostart on boot? (y/n) [default: y]: " AUTO_START
AUTO_START=${AUTO_START:-y}

# Execution steps
log "Script starting, user configuration: port=$PORT, Token=$TOKEN, autostart=$AUTO_START"
check_deps
configure_npm
apply_patches
setup_autostart
activate_wakelock
start_service

echo ""
echo -e "${GREEN}=========================================="
echo -e "✅ OpenClaw initial installation completed, awaiting configuration!"
echo -e "==========================================${NC}"
echo ""
echo -e "OPENCLAW_GATEWAY_TOKEN: ${YELLOW}$TOKEN${NC}"
echo ""
echo -e "${BLUE}┌─────────────────────────────────────┐${NC}"
echo -e "${BLUE}│${NC}  Common Commands                    ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ─────────────────────────────────  ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ${CYAN}oclog${NC}    - View running status       ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ${CYAN}ockill${NC}   - Stop service               ${BLUE}│${NC}"
echo -e "${BLUE}│${NC}  ${CYAN}ocr${NC}      - Restart service            ${BLUE}│${NC}"
echo -e "${BLUE}└─────────────────────────────────────┘${NC}"
echo ""

# dry-run mode skips configuration guide
if [ $DRY_RUN -eq 1 ]; then
    echo -e "${YELLOW}Dry run completed, no actual installation performed${NC}"
    log "Dry run completed"
    exit 0
fi

# Update mode skips configuration guide
if [ $FORCE_UPDATE -eq 1 ]; then
    echo -e "${GREEN}Update completed!${NC}"
    log "Update completed"
    exit 0
fi

# Check if service started normally
if ! tmux has-session -t openclaw 2>/dev/null; then
    echo -e "${RED}Service failed to start, please check logs (openclaw logs) and manually run openclaw onboard${NC}"
    log "Service failed to start"
    exit 1
fi

# Function to display final information
show_final_info() {
    local CONFIGURED=$1
    local SHOW_IGNORE_HINT=$2
    echo ""
    echo -e "${BLUE}┌─────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC}  Common Commands                    ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ─────────────────────────────────  ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}oclog${NC}    - View running status       ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}ockill${NC}   - Stop service               ${BLUE}│${NC}"
    echo -e "${BLUE}│${NC}  ${CYAN}ocr${NC}      - Restart service            ${BLUE}│${NC}"
    echo -e "${BLUE}└─────────────────────────────────────┘${NC}"
    echo ""
    if [ "$CONFIGURED" = "true" ]; then
        echo -e "${GREEN}✅ Configuration completed!${NC}"
        if [ "$SHOW_IGNORE_HINT" = "true" ]; then
            echo ""
            echo -e "If ${YELLOW}'Gateway service install not supported on android'${NC} error appears, it can be ${CYAN}ignored${NC}."
            echo ""
            echo -e "${YELLOW}Do not use openclaw gateway command${NC}, use ${CYAN}ocr${NC} command to start Gateway."
        fi
        echo ""
        echo -e "${CYAN}👉 Next step: Open in phone browser${NC}"
        echo -e "${WHITE_ON_BLUE} http://localhost:$PORT/?token=$TOKEN ${NC}"
        echo -e "Or run command: openclaw tui"
    else
        echo -e "${YELLOW}Please manually run openclaw onboard to continue configuration${NC}"
        if [ "$SHOW_IGNORE_HINT" = "true" ]; then
            echo ""
            echo -e "${YELLOW}During configuration, if 'Gateway service install not supported on android' error appears, it can be ignored.${NC} Also, don't use openclaw gateway command, use ocr command to start."
        fi
    fi
}

# Configuration guide
echo -e "Press ${YELLOW}Enter${NC} key to start configuring OpenClaw."
read -r

echo ""
echo -e "About to execute ${YELLOW}openclaw onboard${NC} command..."
echo ""
echo -e "Please prepare your ${YELLOW}LLM API Key${NC}. Recommended providers: MiniMax (minimax-cn), Zhipu (z-ai), etc."
echo ""
echo -e "After configuration, if ${YELLOW}'Gateway service install not supported on android'${NC} error appears, it can be ${CYAN}ignored${NC}."
echo ""
echo -e "${YELLOW}⚠️ Do not use openclaw gateway command${NC}. Use ${CYAN}ocr${NC} command to start."
echo ""
read -p "Continue? [Y/n]: " CONTINUE_ONBOARD
CONTINUE_ONBOARD=${CONTINUE_ONBOARD:-y}

if [[ "$CONTINUE_ONBOARD" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "Starting openclaw onboard command..."
    echo ""
    # Temporarily unset LD_PRELOAD to fix npm not finding /bin/npm when installing feishu
    OLD_LD_PRELOAD="${LD_PRELOAD:-}"
    unset LD_PRELOAD
    # Catch Ctrl+C (and restore LD_PRELOAD)
    trap 'echo -e "\n${YELLOW}Configuration cancelled${NC}"; [ -n "$OLD_LD_PRELOAD" ] && LD_PRELOAD="$OLD_LD_PRELOAD"; show_final_info "false" "true"; log "User cancelled configuration"' INT
    openclaw onboard
    trap - INT
    # Restore LD_PRELOAD
    [ -n "$OLD_LD_PRELOAD" ] && LD_PRELOAD="$OLD_LD_PRELOAD"

    # Check if configuration file exists and is valid
    if [ -f "$HOME/.openclaw/openclaw.json" ] && node -e "JSON.parse(require('fs').readFileSync('$HOME/.openclaw/openclaw.json'))" 2>/dev/null; then
        # Ensure token in openclaw.json uses environment variable reference
        TOKEN_REF='${OPENCLAW_GATEWAY_TOKEN}'
        if node -e "const fs=require('fs');const p=process.env.HOME+'/.openclaw/openclaw.json';const c=JSON.parse(fs.readFileSync(p,'utf8'));c.gateway=c.gateway||{};c.gateway.auth=c.gateway.auth||{};c.gateway.auth.token='$TOKEN_REF';fs.writeFileSync(p,JSON.stringify(c,null,2));"; then
            log "Updated token in openclaw.json to environment variable reference"
            # Restart gateway to apply new token
            echo -e "${YELLOW}Restarting Gateway service to apply new Token...${NC}"
            pkill -9 -f 'openclaw' 2>/dev/null || true
            tmux kill-session -t openclaw 2>/dev/null || true
            sleep 1
            tmux new -d -s openclaw
            sleep 1
            tmux send-keys -t openclaw "export PATH=$NPM_BIN:\$PATH TMPDIR=\$HOME/tmp OPENCLAW_GATEWAY_TOKEN=$TOKEN; openclaw gateway --bind loopback --port $PORT --token \$OPENCLAW_GATEWAY_TOKEN --allow-unconfigured 2>&1 | tee $LOG_DIR/runtime.log" C-m
            sleep 2
            if tmux has-session -t openclaw 2>/dev/null; then
                log "Gateway restarted successfully"
                echo -e "${GREEN}✅ Gateway service restarted, Token configuration applied${NC}"
            else
                log "Gateway restart failed"
                echo -e "${RED}⚠️ Gateway restart failed, please manually run ocr command${NC}"
            fi
        else
            log "Warning: Failed to update token in openclaw.json"
        fi
        show_final_info "true" "true"
    else
        show_final_info "false" "true"
    fi
    log "Script execution completed"
    
else
    show_final_info "false" "true"
    log "User skipped configuration"
fi

# Return to home directory
cd ~
