---
name: fix-openclaw-shebang-termux
overview: 修复 openclaw 可执行文件的 shebang，将 /usr/bin/env 替换为 Termux 兼容路径
todos:
  - id: fix-shebang
    content: 在 apply_patches() 函数末尾添加 shebang 修复逻辑
    status: completed
---

## 产品概述

修复 OpenClaw 在 Termux 环境下的 shebang 兼容性问题

## 核心功能

- 在 `apply_patches()` 函数中添加修复 shebang 的逻辑
- 将 npm 安装的 openclaw 可执行文件中的 `#!/usr/bin/env node` 替换为 Termux 兼容的 `#!/data/data/com.termux/files/usr/bin/env node`
- 确保安装完成后 `openclaw gateway` 命令能正常执行

## 技术栈

- Shell 脚本 (Bash)
- Termux 环境兼容性处理

## 实现方案

在现有的 `apply_patches()` 函数末尾添加 shebang 修复逻辑：

1. 检测 openclaw 可执行文件是否存在
2. 使用 `sed` 命令替换 shebang 行中的 `/usr/bin/env` 为 `$PREFIX/bin/env`
3. Termux 环境下 `$PREFIX` 通常为 `/data/data/com.termux/files/usr`

## 实现细节

### 修改文件

- `/mnt/d/data/install-openclaw-on-termux.sh/install-openclaw-termux.sh`
- 在 `apply_patches()` 函数的剪贴板修复代码之后、函数结束之前添加 shebang 修复逻辑
- 修复 `$NPM_BIN/openclaw` 可执行文件的 shebang
- 使用 `$PREFIX/bin/env` 替换 `/usr/bin/env`

### 代码逻辑

```
# 修复 openclaw 可执行文件的 shebang（Termux 兼容性）
OPENCLAW_BIN="$NPM_BIN/openclaw"
if [ -f "$OPENCLAW_BIN" ]; then
    log "修复 openclaw 可执行文件的 shebang"
    # 检查是否包含需要修复的 shebang
    if head -n1 "$OPENCLAW_BIN" | grep -q "^#!/usr/bin/env"; then
        # 使用 PREFIX 环境变量获取 Termux 的实际前缀路径
        TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
        sed -i "1s|#!/usr/bin/env|#!${TERMUX_PREFIX}/bin/env|" "$OPENCLAW_BIN"
        echo -e "${GREEN}✓ openclaw shebang 已修复为 Termux 兼容路径${NC}"
    else
        log "openclaw shebang 无需修复"
    fi
fi
```