#!/bin/bash

# ==========================================
# 交互式 UFW 安全配置脚本
# 功能：向导式配置 SSH、Cloudflare 白名单、Docker 容器访问
# ==========================================

# 遇到错误立即退出 (除了 read 命令)
set -e

# --- 颜色定义 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- 辅助函数 ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_ask() { echo -e "${BLUE}[SCENE]${NC} $1"; }

# 检查是否为 Root
if [[ $EUID -ne 0 ]]; then
   log_error "此脚本必须以 root 权限运行"
   exit 1
fi

# 欢迎界面
clear
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}      Linux UFW 防火墙一键安全配置脚本 (交互版)      ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# --- 步骤 1: 环境准备 ---
log_info "正在检查并安装必要环境 (UFW, Curl, Grep)..."
apt-get update -qq >/dev/null
apt-get install -y -qq ufw curl grep >/dev/null

# --- 步骤 2: 收集用户配置 (交互部分) ---

# 2.1 SSH 端口配置
# 自动检测 SSH 端口
AUTO_SSH_PORT=$(grep "^Port " /etc/ssh/sshd_config | awk '{print $2}' | head -n 1)
[ -z "$AUTO_SSH_PORT" ] && AUTO_SSH_PORT=22

echo ""
log_ask "SSH 端口配置"
echo -e "系统检测到的 SSH 端口为: ${YELLOW}${AUTO_SSH_PORT}${NC}"
read -p "是否使用此端口作为 SSH 访问端口? [Y/n] " confirm_ssh
confirm_ssh=${confirm_ssh:-Y}

if [[ "$confirm_ssh" =~ ^[Yy]$ ]]; then
    FINAL_SSH_PORT=$AUTO_SSH_PORT
else
    while true; do
        read -p "请输入您想开放的 SSH 端口 (例如 22): " user_port
        if [[ "$user_port" =~ ^[0-9]+$ ]] && [ "$user_port" -ge 1 ] && [ "$user_port" -le 65535 ]; then
            FINAL_SSH_PORT=$user_port
            break
        else
            log_error "无效端口，请输入 1-65535 之间的数字。"
        fi
    done
fi

# 2.2 Cloudflare 配置
echo ""
log_ask "Cloudflare 白名单配置"
echo "是否限制 80/443 端口仅允许 Cloudflare IP 访问？"
echo "如果你使用 CF CDN，建议选 Y；如果你直连，请选 n。"
read -p "是否开启 CF 白名单? [Y/n] " enable_cf
enable_cf=${enable_cf:-Y}

# 2.3 Docker 配置
echo ""
log_ask "Docker 容器访问配置"
echo "是否允许 Docker 容器访问宿主机(Host)的端口？"
echo "这将放行 172.16.0.0/12 网段 (涵盖 Docker 默认 bridge 和自定义网络)。"
read -p "是否允许容器访问宿主机? [Y/n] " enable_docker
enable_docker=${enable_docker:-Y}

# --- 步骤 3: 最终确认 ---
echo ""
echo -e "${BLUE}================ 配置确认 ================${NC}"
echo -e "1. 重置 UFW:      ${YELLOW}是 (清空所有旧规则)${NC}"
echo -e "2. SSH 端口:      ${YELLOW}${FINAL_SSH_PORT}${NC}"
echo -e "3. CF 白名单:     ${YELLOW}${enable_cf}${NC}"
echo -e "4. Docker 互通:   ${YELLOW}${enable_docker}${NC}"
echo -e "${BLUE}==========================================${NC}"
read -p "按回车键开始应用配置，或按 Ctrl+C 取消..."

# --- 步骤 4: 执行配置 ---

log_info "正在重置防火墙规则..."
ufw --force reset >/dev/null

log_info "设置默认策略 (拒绝入站，允许出站)..."
ufw default deny incoming
ufw default allow outgoing

log_info "开放 SSH 端口: $FINAL_SSH_PORT"
ufw allow "$FINAL_SSH_PORT"/tcp >/dev/null

# 处理 Cloudflare
if [[ "$enable_cf" =~ ^[Yy]$ ]]; then
    CF_IPV4_URL="https://www.cloudflare.com/ips-v4"
    CF_IPV6_URL="https://www.cloudflare.com/ips-v6"

    add_cf_rules() {
        local url=$1
        local type=$2
        log_info "正在获取并添加 Cloudflare $type 规则..."
        
        if ! ips=$(curl -s --connect-timeout 10 --retry 3 "$url"); then
            log_error "无法获取 $type 列表，跳过。"
            return
        fi

        if [ -z "$ips" ]; then
            log_error "$type 列表为空，跳过。"
            return
        fi

        echo "$ips" | while read -r ip; do
            [ -z "$ip" ] && continue
            ufw allow from "$ip" to any port 80 proto tcp >/dev/null
            ufw allow from "$ip" to any port 443 proto tcp >/dev/null
        done
    }

    add_cf_rules "$CF_IPV4_URL" "IPv4"
    add_cf_rules "$CF_IPV6_URL" "IPv6"
else
    log_warn "跳过 Cloudflare 白名单，直接开放 80/443 全网访问..."
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
fi

# 处理 Docker
if [[ "$enable_docker" =~ ^[Yy]$ ]]; then
    log_info "正在添加 Docker 容器访问宿主机许可 (172.16.0.0/12)..."
    ufw allow from 172.16.0.0/12 >/dev/null
fi

# --- 步骤 5: 启用与展示 ---
log_info "正在启用 UFW..."
ufw --force enable

echo ""
log_info "配置完成！最终规则列表如下："
ufw status numbered
