#!/bin/bash

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 0. 权限检测 (Root兼容核心) ---
SUDO_CMD=""
if [ "$EUID" -ne 0 ]; then
    # 如果不是 root，检查 sudo 是否存在
    if command -v sudo &> /dev/null; then
        SUDO_CMD="sudo"
        echo -e "${BLUE}[INFO]${NC} 检测到普通用户，将使用 sudo 提权。"
    else
        echo -e "${RED}[ERROR]${NC} 你是普通用户但未安装 sudo，脚本无法继续。"
        exit 1
    fi
else
    echo -e "${YELLOW}[WARN]${NC} 检测到 Root 用户。将直接在 /root 目录下配置环境。"
    # 对于 npm，root 用户有时需要特殊标志
    NPM_ROOT_FLAGS="--unsafe-perm=true --allow-root"
fi

# --- 辅助函数 ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# 交互确认函数
confirm() {
    echo -n -e "${YELLOW}[?] $1 (y/n) [默认y]: ${NC}"
    read -r response
    response=${response,,} # 转小写
    if [[ -z "$response" || "$response" =~ ^y$ ]]; then
        return 0
    else
        return 1
    fi
}

# --- 1. 系统更新与基础依赖 ---
step_system_update() {
    log_info "准备更新 apt 源并安装: curl, wget, git, build-essential, fish"
    if confirm "是否执行系统更新和基础安装？"; then
        $SUDO_CMD apt update -y
        # 增加 sudo 安装 (防止某些极简 Docker 镜像连 sudo 都没有，虽然 root 不用，但某些工具依赖)
        $SUDO_CMD apt install curl wget unzip git build-essential fish -y
        log_success "基础依赖安装完成"
    else
        log_warn "跳过系统更新"
    fi
}

# --- 2. 配置 Fish Shell ---
step_fish_setup() {
    if confirm "是否将 Fish 设为默认 Shell 并安装 Fisher 插件管理器？"; then
        # 设为默认
        CURRENT_SHELL=$(grep "^$USER" /etc/passwd | cut -d: -f7)
        FISH_PATH=$(which fish)
        if [[ "$CURRENT_SHELL" != "$FISH_PATH" ]]; then
            $SUDO_CMD chsh -s "$FISH_PATH" "$USER"
            log_success "默认 Shell 已修改 (需注销或重启终端生效)"
        fi

        # 安装 Fisher (在 fish 进程中执行)
        log_info "正在安装 Fisher..."
        # 注意：fish -c 会使用当前用户的环境，Root 下也没问题
        fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
        log_success "Fisher 安装完成"
    else
        log_warn "跳过 Fish 配置"
    fi
}

# --- 3. Rust 环境与工具 ---
step_rust_setup() {
    # 3.1 安装 Rust
    if confirm "是否安装 Rust 基础环境 (rustup + cargo)？"; then
        if ! command -v rustc &> /dev/null; then
            # Root 下通常不需要 sudo，rustup 会安装到 ~/.cargo
            curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
            source "$HOME/.cargo/env"
            log_success "Rust 安装完成"
        else
            log_info "Rust 已存在，跳过安装"
        fi
    else
        log_warn "跳过 Rust 环境安装"
        return
    fi

    # 3.2 安装工具
    log_info "即将安装 Rust 工具: ripgrep, fd, bat, eza, zoxide, bottom, starship"
    log_warn "注意：这需要从源码编译，耗时较长 (5-15分钟)。"
    if confirm "是否编译安装这些工具？"; then
        source "$HOME/.cargo/env"
        TOOLS="ripgrep fd-find bat eza zoxide bottom starship"
        for tool in $TOOLS; do
            if ! cargo install --list | grep -q "^$tool "; then
                echo "正在编译 $tool ..."
                cargo install "$tool"
            else
                echo "$tool 已安装"
            fi
        done
        log_success "Rust 工具集安装完成"
    else
        log_warn "跳过 Rust 工具编译"
    fi
}

# --- 4. 运行时 (Node & Python) ---
step_runtimes() {
    # Python uv
    if confirm "是否安装 uv (极速 Python 包管理器)？"; then
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi

    # Node fnm
    if confirm "是否安装 fnm (Node.js 管理器) 及 Node LTS？"; then
        # fnm 在 root 下安装到 /root/.local/share/fnm，这是完全合法的
        curl -fsSL https://fnm.vercel.app/install | bash
        
        # 临时激活
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "`fnm env`"
        fnm install --lts
        fnm use lts
        log_success "Node.js $(node -v) 安装完成"
    fi
}

# --- 5. 写入配置文件 ---
step_config_files() {
    log_warn "即将覆盖 ~/.config/fish/config.fish"
    if confirm "是否写入 Fish 和 Starship 的配置文件？"; then
        mkdir -p ~/.config/fish
        mkdir -p ~/.config/fish/functions

        # 使用 cat EOF 写入，这里不用 sudo，因为配置的是当前用户(可能是root)的目录
        cat > ~/.config/fish/config.fish << 'EOF'
# --- 1. 路径配置 (优先级最高) ---
fish_add_path ~/.cargo/bin
fish_add_path ~/.local/share/fnm
fish_add_path ~/.local/bin

# --- 2. 交互式配置 ---
if status is-interactive
    # Starship
    starship init fish | source
    # Fnm
    fnm env --use-on-cd | source
    # Zoxide
    zoxide init fish | source

    # --- Aliases ---
    alias ls="eza --icons --git"
    alias ll="eza --icons --git -l -h"
    alias tree="eza --icons --tree --level=2"
    alias cat="bat"
    alias grep="rg"
    alias find="fd"
    alias top="btm"
    
    # AI CLI: 增加 root 兼容参数
    alias cc="claude --dangerously-skip-permissions"
end
EOF
        
        # Starship 配置
        mkdir -p ~/.config
        echo "add_newline = false" > ~/.config/starship.toml
        log_success "配置文件写入完成"
    else
        log_warn "跳过配置文件写入"
    fi
}

# --- 6. AI 工具链 ---
step_ai_tools() {
    if confirm "是否安装 AI CLI (Gemini, Codex, Claude)？"; then
        export PATH="$HOME/.local/share/fnm:$PATH"
        eval "`fnm env`"
        
        if command -v npm &> /dev/null; then
            log_info "正在通过 npm 安装 AI 工具 (可能需要几分钟)..."
            # 这里的 NPM_ROOT_FLAGS 确保在 Root 下安装不会报错
            npm install -g @google/gemini-cli $NPM_ROOT_FLAGS
            npm install -g @openai/codex $NPM_ROOT_FLAGS
            npm install -g @anthropic-ai/claude-code $NPM_ROOT_FLAGS
            log_success "AI CLI 工具安装完成"
        else
            log_warn "未检测到 npm，请先安装 Runtime。"
        fi
    fi
}

# --- 7. Git 配置 ---
step_git_config() {
    if confirm "是否现在配置 Git 用户信息？"; then
        echo -e "${BLUE}请输入 Git 用户名 (User Name):${NC}"
        read -r git_name
        
        echo -e "${BLUE}请输入 Git 邮箱 (User Email):${NC}"
        read -r git_email

        if [[ -n "$git_name" && -n "$git_email" ]]; then
            git config --global user.name "$git_name"
            git config --global user.email "$git_email"
            # 解决 Root 目录下 Git 有时会报 unsafe directory 的问题
            git config --global --add safe.directory "*"
            log_success "Git 配置已更新"
        else
            log_warn "输入为空，跳过。"
        fi
    else
        log_warn "跳过 Git 配置"
    fi
}

# --- 主程序 ---
clear
echo -e "${GREEN}=============================================${NC}"
echo -e "   Linux 开发环境交互式配置向导 (Root兼容版)   "
echo -e "${GREEN}=============================================${NC}"
echo "当前用户: $(whoami) (UID: $EUID)"
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}警告: 您正在以 ROOT 身份运行。环境将配置在 /root 下。${NC}"
fi
echo ""
echo "按 Enter 键选择默认 [y] (是)，输入 n 选择 [no] (否)"
echo ""

step_system_update
echo ""
step_fish_setup
echo ""
step_rust_setup
echo ""
step_runtimes
echo ""
step_config_files
echo ""
step_ai_tools
echo ""
step_git_config

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   所有配置已完成！  ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo "建议输入 'fish' 进入新环境测试。"
