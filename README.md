# 🚀 Debian 13 TCP 调优脚本

专为 **Debian 13 (Trixie)** 及其搭载的 **Linux Kernel 6.12+** 量身定制的现代化 TCP 调优方案。
本脚本摒弃了过时的参数，基于新版内核特性进行优化，旨在在保证系统稳定性的前提下，最大化高延迟网络环境下的吞吐量。

## ⚡ 快速安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/NakanoSanku/vps/refs/heads/main/tcp_optimize_debian13.sh)
```

## ✨ 核心亮点

  * **🚀 原生 BBR 启用**
    无需编译或替换内核，直接调用 Debian 13 内核自带的模块，启用标准的 `bbr` + `fq` 拥塞控制算法。
  * **⚡ 现代网络栈优化**
    针对 Kernel 6.x 调整 TCP 窗口大小、缓冲区（Buffer）及队列长度，显著提升大带宽、高延迟环境下的连接速度。
  * **🛡️ 安全与备份**
    **自动备份**原有的 `/etc/sysctl.conf`，并在执行前检查环境，防止配置错误导致失联。
  * **📂 非侵入式配置**
    采用模块化设计，配置写入独立的 `/etc/sysctl.d/99-vps-tuning.conf`，保持系统主配置文件整洁，易于管理和回滚。

## 📊 优化效果对比

> 测试环境：Debian 13 / Kernel 6.12 / 国际互联线路

<img width="600" height="700" alt="image" src="https://github.com/user-attachments/assets/59492a0b-d1d2-4c0a-ad44-701b2d16cbf5" />

# 🛡️ UFW Firewall Auto Setup | UFW 防火墙一键安全配置

这是一个交互式的 Bash 脚本，旨在为 Linux VPS (Debian/Ubuntu) 提供开箱即用的安全防火墙配置。它解决了手动配置 UFW 时常见的 SSH 误封、Cloudflare 规则繁琐以及 Docker 容器无法访问宿主机等痛点。

## ✨ 主要功能 (Features)

  * ✅ **SSH 安全防护**：自动检测当前 SSH 端口（即使非 22 端口），防止将自己锁在服务器外。
  * ☁️ **Cloudflare 集成**：(可选) 自动拉取 Cloudflare 最新 IPv4/IPv6 列表，仅允许 CF 流量访问 80/443 端口，隐藏源站 IP。
  * 🐳 **Docker 友好**：(可选) 智能放行 `172.16.0.0/12` 网段，解决容器无法连接宿主机数据库/服务的问题。
  * 🤖 **交互式引导**：全程向导式操作，并在执行前提供最终确认。

## 🚀 快速开始 (Quick Start)

无需下载文件，直接在服务器终端执行以下命令即可（需要 Root 权限）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/NakanoSanku/vps/refs/heads/main/ufw.sh)
```

## 📋 脚本逻辑

1.  **环境检查**：自动安装 `ufw`, `curl` 等必要组件。
2.  **重置规则**：清空旧的防火墙规则，确保环境纯净。
3.  **默认策略**：拒绝入站，允许出站。
4.  **规则应用**：根据你的选择，依次放行 SSH、Cloudflare IP 段和 Docker 网段。
5.  **启用服务**：最后启用 UFW 并展示状态。

# 🛠️ Linux Dev Setup | 交互式全能开发环境配置

这是一个基于 `whiptail` 的图形化交互脚本，专为开发者设计。它能在一杯咖啡的时间内，将一台崭新的 Debian/Ubuntu 服务器配置为功能强大的现代化开发机。

支持 **Root** 和 **Sudo 用户**，提供“先勾选、后自动执行”的流畅体验。

## ⚡ 快速开始

```bash
bash <(curl -sL https://raw.githubusercontent.com/NakanoSanku/vps/refs/heads/main/setup.sh)
```

## ✨ 核心功能

  * **🎨 TUI 图形菜单**
    采用 Checkbox 勾选模式，支持批量选择任务（系统更新、Shell配置、环境安装等），一次配置，无人值守自动执行。
  * **⚡ 极速 Rust 工具链**
    拒绝漫长的源码编译！利用 `cargo-binstall` 二进制加速安装 `rg` (ripgrep), `fd`, `bat`, `eza`, `zoxide`, `bottom` 等现代化 CLI 工具。
  * **🐚 现代化 Shell 体验**
    一键配置 **Fish Shell** + **Starship** 高性能提示符，预装 Fisher 插件管理器，并写入最佳实践的 Alias 配置。
  * **🔧 多语言运行时**
    集成下一代高速包管理器：**fnm** (Node.js) 和 **uv** (Python)，环境隔离更干净。
  * **🤖 AI CLI 集成**
    (可选) 一键安装 Claude, Gemini, Codex 等 AI 命令行工具。
  * **🔑 SSH & Git 自动化**
    交互式配置 Git 用户信息，并自动生成 GitHub 专用的 **SSH Ed25519** 密钥，生成后自动展示公钥方便复制。
