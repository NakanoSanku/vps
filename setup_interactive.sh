#!/bin/bash

# ==========================================================
#  Linux 开发环境配置向导 (v3.1 SSH增强版)
#  新增：GitHub SSH Key 自动生成与展示
# ==========================================================

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 全局配置 ---
CONFIG_DIR="$HOME/.config"
BACKUP_SUFFIX="_backup_$(date +%Y%m%d_%H%M%S)"
# 存储用户选择的任务
SELECTED_TASKS=""
# 全局变量存储邮箱，用于SSH生成
GLOBAL_GIT_EMAIL=""

# --- 0. 基础环境与权限检测 ---
prepare_env() {
    # 1. 权限检测
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo &> /dev/null; then
            SUDO_CMD="sudo"
        else
            echo -e "${RED}[ERROR] 需要 sudo 权限或 root 用户。${NC}"
            exit 1
        fi
        NPM_ROOT_FLAGS=""
    else
        echo -e "${YELLOW}[WARN] 正在以 ROOT 运行。${NC}"
        SUDO_CMD=""
        NPM_ROOT_FLAGS="--unsafe-perm=true --allow-root"
    fi

    # 2. 检测 whiptail
    if ! command -v whiptail &> /dev/null; then
        echo -e "${BLUE}[INFO] 正在安装界面库 (whiptail)...${NC}"
        $SUDO_CMD apt update -y &> /dev/null
        $SUDO_CMD apt install whiptail -y &> /dev/null
    fi
}

# --- 辅助函数 ---
log_step() { echo -e "\n${CYAN}>>> [执行中] $1${NC}"; }
log_success() { echo -e "${GREEN}[完成] $1${NC}"; }
log_warn() { echo -e "${YELLOW}[注意] $1${NC}"; }
log_info() { echo -e "${BLUE}[信息] $1${NC}"; }

backup_file() {
    local file_path="$1"
    if [ -f "$file_path" ]; then
        cp "$file_path" "${file_path}${BACKUP_SUFFIX}"
        echo -e "${YELLOW}  已备份: $(basename "$file_path")${BACKUP_SUFFIX}${NC}"
    fi
}

# --- 菜单界面 ---
show_menu() {
    SELECTED_TASKS=$(whiptail --title "Linux 开发环境配置向导" --checklist \
    "请按 [空格键] 勾选/取消，[回车键] 确认" 22 78 11 \
    "SYS_UPD"   "系统更新 & 基础依赖 (curl, git, fish)" ON \
    "FISH_CFG"  "设置 Fish 为默认 Shell 并安装 Fisher" ON \
    "RUST_ENV"  "安装 Rust 环境 (Rustup)" ON \
    "RUST_TLS"  "安装 Rust 命令行工具 (二进制加速)" ON \
    "RUNTIMES"  "安装 Node.js (fnm) & Python (uv)" ON \
    "WR_CONF"   "覆盖写入 Fish & Starship 配置文件" ON \
    "AI_TOOLS"  "安装 AI CLI (Claude, Gemini, Codex)" OFF \
    "GIT_CFG"   "配置 Git 用户名与邮箱" OFF \
    "SSH_KEY"   "生成 SSH 密钥 (用于 GitHub 访问)" OFF \
    3>&1 1>&2 2>&3)

    if [ $? != 0 ]; then
        echo "用户取消操作。"
        exit 0
    fi
}

# --- 任务执行函数 ---

task_sys_update() {
    log_step "系统更新与基础依赖"
    $SUDO_CMD apt update -y
    $SUDO_CMD apt install -y curl wget unzip git build-essential fish ca-certificates gnupg
    log_success "基础依赖安装完毕"
}

task_fish_cfg() {
    log_step "配置 Fish Shell"
    FISH_PATH=$(which fish)
    if [[ -n "$FISH_PATH" && "$SHELL" != "$FISH_PATH" ]]; then
        if ! grep -q "$FISH_PATH" /etc/shells; then
            echo "$FISH_PATH" | $SUDO_CMD tee -a /etc/shells
        fi
        $SUDO_CMD chsh -s "$FISH_PATH" "$USER"
        log_success "默认 Shell 已修改"
    fi
    fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
    log_success "Fisher 已安装"
}

task_rust_env() {
    log_step "安装 Rust (Rustup)"
    if ! command -v rustc &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        log_success "Rust 安装完成"
    else
        source "$HOME/.cargo/env"
        log_info "Rust 已存在"
    fi
}

task_rust_tools() {
    log_step "安装 Rust 工具 (Cargo Binstall)"
    source "$HOME/.cargo/env"
    if ! command -v cargo-binstall &> /dev/null; then
        curl -L --proto '=https' --tlsv1.2 -sSf https://raw.githubusercontent.com/cargo-bins/cargo-binstall/main/install-from-binstall-release.sh | bash
    fi

    TOOLS="ripgrep fd-find bat eza zoxide bottom starship"
    for tool in $TOOLS; do
        local bin_name=$tool
        [[ "$tool" == "fd-find" ]] && bin_name="fd"
        [[ "$tool" == "ripgrep" ]] && bin_name="rg"
        [[ "$tool" == "bottom" ]] && bin_name="btm"

        if ! command -v "$bin_name" &> /dev/null; then
            echo "安装 $tool ..."
            cargo binstall -y "$tool"
        else
            echo "✔ $tool 已存在"
        fi
    done
    log_success "Rust 工具集就绪"
}

task_runtimes() {
    log_step "安装 Runtimes"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    curl -fsSL https://fnm.vercel.app/install | bash
    export PATH="$HOME/.local/share/fnm:$PATH"
    eval "$(fnm env --shell bash)"
    fnm install --lts
    fnm use lts
    log_success "Node & Python(uv) 安装完毕"
}

task_write_conf() {
    log_step "写入配置文件"
    mkdir -p "$CONFIG_DIR/fish"
    backup_file "$CONFIG_DIR/fish/config.fish"
    
    cat > "$CONFIG_DIR/fish/config.fish" << 'EOF'
fish_add_path $HOME/.cargo/bin
fish_add_path $HOME/.local/share/fnm
fish_add_path $HOME/.local/bin

if status is-interactive
    if type -q starship; starship init fish | source; end
    if type -q fnm; fnm env --use-on-cd | source; end
    if type -q zoxide; zoxide init fish | source; end
    
    if type -q eza
        alias ls="eza --icons --git"
        alias ll="eza --icons --git -l -h"
        alias tree="eza --icons --tree --level=2"
    end
    if type -q bat; alias cat="bat"; end
    if type -q rg; alias grep="rg"; end
    if type -q fd; alias find="fd"; end
    alias cc="claude --dangerously-skip-permissions"
end
EOF
    echo "add_newline = false" > "$CONFIG_DIR/starship.toml"
    log_success "配置文件更新"
}

task_ai_tools() {
    log_step "安装 AI CLI"
    export PATH="$HOME/.local/share/fnm:$PATH"
    if command -v fnm &> /dev/null; then eval "$(fnm env --shell bash)"; fi

    if command -v npm &> /dev/null; then
        npm install -g @google/gemini-cli $NPM_ROOT_FLAGS
        npm install -g @anthropic-ai/claude-code $NPM_ROOT_FLAGS
        log_success "AI 工具安装完毕"
    fi
}

task_git_cfg() {
    log_step "Git 用户配置"
    echo -e "${YELLOW}请输入 Git 信息 (直接回车跳过):${NC}"
    echo -n "User Name: "
    read -r git_name
    echo -n "User Email: "
    read -r git_email

    if [[ -n "$git_name" && -n "$git_email" ]]; then
        git config --global user.name "$git_name"
        git config --global user.email "$git_email"
        git config --global --add safe.directory "*"
        GLOBAL_GIT_EMAIL="$git_email" # 保存给 SSH 步骤使用
        log_success "Git 配置更新"
    else
        log_info "跳过 Git 配置"
    fi
}

task_ssh_key() {
    log_step "生成 GitHub SSH 密钥 (Ed25519)"
    KEY_PATH="$HOME/.ssh/id_ed25519"

    # 1. 检查是否存在
    if [ -f "$KEY_PATH" ]; then
        log_warn "检测到已有密钥: $KEY_PATH"
        log_info "跳过生成，仅显示现有公钥..."
    else
        # 2. 获取邮箱 (优先使用刚才 Git 配置的，没有则尝试读取 git config，再没有则用默认)
        if [ -z "$GLOBAL_GIT_EMAIL" ]; then
            GLOBAL_GIT_EMAIL=$(git config --global user.email)
        fi
        if [ -z "$GLOBAL_GIT_EMAIL" ]; then
            GLOBAL_GIT_EMAIL="$USER@$(hostname)"
        fi

        echo "使用邮箱标识: $GLOBAL_GIT_EMAIL"
        # -N "" 表示空密码，方便自动化；-f 指定路径
        mkdir -p ~/.ssh
        ssh-keygen -t ed25519 -C "$GLOBAL_GIT_EMAIL" -f "$KEY_PATH" -N ""
        log_success "密钥生成完成"
    fi

    # 3. 启动 ssh-agent 并添加
    if ! pgrep -u "$USER" ssh-agent > /dev/null; then
        eval "$(ssh-agent -s)" > /dev/null
    fi
    ssh-add "$KEY_PATH" > /dev/null 2>&1

    # 4. 醒目展示
    echo -e "\n${YELLOW}================================================================${NC}"
    echo -e "${YELLOW}请复制下方公钥 (Public Key) 添加到 GitHub -> Settings -> SSH Keys:${NC}"
    echo -e "${GREEN}----------------------------------------------------------------${NC}"
    cat "${KEY_PATH}.pub"
    echo -e "${GREEN}----------------------------------------------------------------${NC}"
    echo -e "${YELLOW}================================================================${NC}\n"
    
    # 暂停等待用户复制
    read -n 1 -s -r -p ">>> 请复制上方密钥，完成后按任意键继续..."
    echo ""
}

# --- 主流程 ---
main() {
    prepare_env
    show_menu
    clear

    # 根据选择执行
    if [[ $SELECTED_TASKS == *"SYS_UPD"* ]]; then task_sys_update; fi
    if [[ $SELECTED_TASKS == *"FISH_CFG"* ]]; then task_fish_cfg; fi
    if [[ $SELECTED_TASKS == *"RUST_ENV"* ]]; then task_rust_env; fi
    if [[ $SELECTED_TASKS == *"RUST_TLS"* ]]; then task_rust_tools; fi
    if [[ $SELECTED_TASKS == *"RUNTIMES"* ]]; then task_runtimes; fi
    if [[ $SELECTED_TASKS == *"WR_CONF"* ]]; then task_write_conf; fi
    if [[ $SELECTED_TASKS == *"AI_TOOLS"* ]]; then task_ai_tools; fi
    
    # 交互式配置放在最后
    if [[ $SELECTED_TASKS == *"GIT_CFG"* ]]; then task_git_cfg; fi
    if [[ $SELECTED_TASKS == *"SSH_KEY"* ]]; then task_ssh_key; fi

    echo -e "\n${GREEN}=========================================${NC}"
    echo -e "${GREEN}   ✅ 所有配置已完成！   ${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "建议执行: ${YELLOW}exec fish${NC} 进入新环境。"
}

main
