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
