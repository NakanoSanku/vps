# 🚀 Debian 13 TCP 调优脚本

专为 **Debian 13 (Trixie)** 及其搭载的 **Linux Kernel 6.12+** 量身定制的现代化 TCP 调优方案。
本脚本摒弃了过时的参数，基于新版内核特性进行优化，旨在在保证系统稳定性的前提下，最大化高延迟网络环境下的吞吐量。

## ⚡ 快速安装

```bash
bash <(curl -sL https://raw.githubusercontent.com/NakanoSanku/vps/refs/heads/main/tcp_optimize_debian13)
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
