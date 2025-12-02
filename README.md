# vps
# Debian 13 TCP调优
VPS 一键 TCP 调优脚本，专门针对 Debian 13 (Trixie) 及其搭载的 Linux Kernel 6.12+ 进行了适配。
这个脚本采用了现代化的调优思路（开启 BBR、优化缓冲区、调整连接追踪），并且注重安全性（会自动备份原配置）。
脚本功能亮点
- 自动开启 BBR: Debian 13 内核默认已包含 BBR 模块，脚本会直接开启 bbr + fq。
- 现代网络优化: 针对 6.x 内核优化了 TCP 窗口大小、缓冲区和队列长度，提升高延迟网络下的吞吐量。
- 安全备份: 执行前会自动备份 /etc/sysctl.conf，防止配置出错无法还原。
- 模块化配置: 将配置写入独立的 /etc/sysctl.d/99-vps-tuning.conf 文件，保持系统整洁。
```
bash <(curl -sL https://raw.githubusercontent.com/NakanoSanku/vps/refs/heads/main/tcp_optimize_debian13)
```
## 🌐网络质量
<img width="745" height="968" alt="image" src="https://github.com/user-attachments/assets/59492a0b-d1d2-4c0a-ad44-701b2d16cbf5" />

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
