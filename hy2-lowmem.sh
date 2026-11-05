#!/bin/sh
# hy2-lowmem.sh - 面向低内存机器（含 64MB 容器 / NAT VPS）的 Hysteria2 一键配置脚本
#
# 用法:
#   sh hy2-lowmem.sh [install] [选项]     安装或更新（默认）
#   sh hy2-lowmem.sh show                 显示分享链接
#   sh hy2-lowmem.sh status               显示服务和内存状态
#   sh hy2-lowmem.sh uninstall [--yes]    卸载
#
# 常用示例:
#   sh hy2-lowmem.sh --dry-run                        只检测并显示计划，不做改动
#   sh hy2-lowmem.sh --port 28443                     指定监听端口
#   sh hy2-lowmem.sh --port 10000 --public-port 28443 NAT：内部 10000 映射到外部 28443
#
# 运行 sh hy2-lowmem.sh --help 查看全部选项。

set -eu
umask 077

REPO="apernet/hysteria"
SVC_NAME="hysteria-server"
SVC_USER="hysteria"

# 选项默认值
CMD="install"
PORT=""
PUBLIC_PORT=""
PUBLIC_HOST=""
SNI=""
AUTH=""
OBFS=""
USE_OBFS=""
VERSION=""
MEM_OVERRIDE=""
PREFIX=""
NO_SERVICE=0
NO_TEST=0
DRY_RUN=0
RECONFIGURE=0
ASSUME_YES=0

# 运行时状态（供 cleanup 使用）
DL_DIR=""
SERVER_PID=""
CLIENT_PID=""
TEST_CFG=""
TEST_SRV_LOG=""
TEST_CLI_LOG=""

info() { printf '[hy2] %s\n' "$*"; }
warn() { printf '[hy2] 警告: %s\n' "$*" >&2; }
die() {
    printf '[hy2] 错误: %s\n' "$*" >&2
    exit 1
}
has() { command -v "$1" >/dev/null 2>&1; }

usage() {
    cat <<'EOF'
用法: sh hy2-lowmem.sh [install|show|status|uninstall] [选项]

安装选项:
  --port N             容器/主机内部监听的 UDP 端口（1024-65535，默认随机 20000 以上）
  --public-port N      对外端口，用于 NAT 映射（默认与 --port 相同）
  --public-host HOST   写入分享链接的地址（默认自动检测公网 IPv4）
  --sni NAME           自签名证书和链接使用的 SNI（默认 www.bing.com）
  --password STR       认证密码（默认随机；仅限 A-Za-z0-9._~-）
  --obfs-password STR  Salamander 混淆密码（默认随机）
  --no-obfs            关闭混淆
  --version TAG        指定版本，如 app/v2.13.0（默认最新版）
  --mem-mb N           手动指定内存上限，跳过自动检测
  --reconfigure        覆盖现有配置（已有脚本记录时保留未指定的端口和密码）
  --no-test            跳过安装后的自检
  --no-service         不注册服务（用于无 init 的容器；自检时临时启动）
  --prefix DIR         安装到 DIR 下而不是系统路径（隐含 --no-service，可不用 root）
  --dry-run            只检测并显示计划，不做任何改动

其他:
  --yes                卸载时不再询问
  -h, --help           显示帮助
EOF
}

need_val() {
    [ "$#" -ge 2 ] && [ -n "$2" ] || die "选项 $1 需要一个值"
}

parse_args() {
    case "${1:-}" in
    install | show | status | uninstall)
        CMD="$1"
        shift
        ;;
    esac
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --port) need_val "$@"; PORT="$2"; shift 2 ;;
        --public-port) need_val "$@"; PUBLIC_PORT="$2"; shift 2 ;;
        --public-host) need_val "$@"; PUBLIC_HOST="$2"; shift 2 ;;
        --sni) need_val "$@"; SNI="$2"; shift 2 ;;
        --password) need_val "$@"; AUTH="$2"; shift 2 ;;
        --obfs-password) need_val "$@"; OBFS="$2"; USE_OBFS=1; shift 2 ;;
        --no-obfs) USE_OBFS=0; shift ;;
        --version) need_val "$@"; VERSION="$2"; shift 2 ;;
        --mem-mb) need_val "$@"; MEM_OVERRIDE="$2"; shift 2 ;;
        --prefix) need_val "$@"; PREFIX="${2%/}"; NO_SERVICE=1; shift 2 ;;
        --no-service) NO_SERVICE=1; shift ;;
        --no-test) NO_TEST=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --reconfigure) RECONFIGURE=1; shift ;;
        --yes) ASSUME_YES=1; shift ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; die "未知参数: $1" ;;
        esac
    done

    if [ -n "$AUTH" ] || [ -n "$OBFS" ]; then
        [ "$USE_OBFS" != 0 ] || [ -z "$OBFS" ] || die "--no-obfs 与 --obfs-password 不能同时使用"
    fi
    [ -z "$AUTH" ] || is_safe_secret "$AUTH" || die "--password 只能包含 A-Za-z0-9._~-"
    [ -z "$OBFS" ] || is_safe_secret "$OBFS" || die "--obfs-password 只能包含 A-Za-z0-9._~-"
    [ -z "$SNI" ] || is_safe_host "$SNI" || die "--sni 格式不正确"
    [ -z "$PUBLIC_HOST" ] || is_safe_host "$PUBLIC_HOST" || die "--public-host 格式不正确"
    [ -z "$PORT" ] || is_port "$PORT" 1024 || die "--port 必须是 1024-65535 的整数"
    [ -z "$PUBLIC_PORT" ] || is_port "$PUBLIC_PORT" 1 || die "--public-port 必须是 1-65535 的整数"
    case "$MEM_OVERRIDE" in
    "") ;;
    *[!0-9]*) die "--mem-mb 必须是整数" ;;
    esac
    case "$VERSION" in
    "" | app/v[0-9]*.[0-9]*.[0-9]*) ;;
    *) die "--version 格式应类似 app/v2.13.0" ;;
    esac
    case "$PREFIX" in
    "" | /*) ;;
    *) die "--prefix 必须是绝对路径" ;;
    esac
}

is_safe_secret() {
    case "$1" in
    *[!A-Za-z0-9._~-]*) return 1 ;;
    *) return 0 ;;
    esac
}
is_safe_host() {
    case "$1" in
    *[!A-Za-z0-9.:-]*) return 1 ;;
    *) return 0 ;;
    esac
}
is_port() {
    case "$1" in
    "" | *[!0-9]*) return 1 ;;
    esac
    [ "${#1}" -le 5 ] && [ "$1" -ge "$2" ] && [ "$1" -le 65535 ]
}

set_paths() {
    BIN="$PREFIX/usr/local/bin/hysteria"
    CONF_DIR="$PREFIX/etc/hysteria"
    CONF_FILE="$CONF_DIR/config.yaml"
    CERT_FILE="$CONF_DIR/server.crt"
    KEY_FILE="$CONF_DIR/server.key"
    STATE_FILE="$CONF_DIR/hy2-lowmem.state"
    LOG_FILE="$PREFIX/var/log/hysteria.log"
}

# ---------- 检测 ----------

detect_mem_mb() {
    if [ -n "$MEM_OVERRIDE" ]; then
        echo "$MEM_OVERRIDE"
        return
    fi
    # 同时看 /proc/meminfo 和 cgroup：容器里 free 显示的往往是宿主机内存，cgroup 才是真实上限。
    {
        awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo
        for f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/memory/memory.limit_in_bytes; do
            [ -r "$f" ] || continue
            awk '$1 ~ /^[0-9]+$/ {print int($1/1048576)}' "$f"
        done
    } | sort -n | head -n 1
}

# 按内存上限选择运行参数；窗口上限决定了每个连接最多缓存多少数据。
select_profile() {
    MEM_MB="$1"
    if [ "$MEM_MB" -le 96 ]; then
        PROFILE="tiny"
        STREAM_INIT=1048576 STREAM_MAX=2097152
        CONN_INIT=2097152 CONN_MAX=4194304
        MAX_STREAMS=256 GOGC_VALUE=50
    elif [ "$MEM_MB" -le 192 ]; then
        PROFILE="small"
        STREAM_INIT=2097152 STREAM_MAX=4194304
        CONN_INIT=4194304 CONN_MAX=8388608
        MAX_STREAMS=512 GOGC_VALUE=75
    elif [ "$MEM_MB" -le 512 ]; then
        PROFILE="medium"
        STREAM_INIT=4194304 STREAM_MAX=8388608
        CONN_INIT=8388608 CONN_MAX=16777216
        MAX_STREAMS=1024 GOGC_VALUE=100
    else
        PROFILE="large"
        STREAM_INIT=8388608 STREAM_MAX=16777216
        CONN_INIT=16777216 CONN_MAX=33554432
        MAX_STREAMS=1024 GOGC_VALUE=100
    fi
    GOMEM_MB=$((MEM_MB * 5 / 8))
    [ "$GOMEM_MB" -ge 24 ] || GOMEM_MB=24
    [ "$GOMEM_MB" -le 512 ] || GOMEM_MB=512
}

detect_asset() {
    case "$(uname -m)" in
    x86_64 | amd64)
        # avx 版本按 GOAMD64=v3 编译，只有 avx 不够，需要 avx2 等指令集。
        flags="$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null || true)"
        case " $flags " in
        *" avx2 "*)
            case " $flags " in
            *" bmi2 "*)
                case " $flags " in
                *" fma "*) ASSET="hysteria-linux-amd64-avx" ;;
                *) ASSET="hysteria-linux-amd64" ;;
                esac
                ;;
            *) ASSET="hysteria-linux-amd64" ;;
            esac
            ;;
        *) ASSET="hysteria-linux-amd64" ;;
        esac
        ;;
    aarch64 | arm64) ASSET="hysteria-linux-arm64" ;;
    armv7* | armv6*) ASSET="hysteria-linux-arm" ;;
    armv5*) ASSET="hysteria-linux-armv5" ;;
    i?86) ASSET="hysteria-linux-386" ;;
    riscv64) ASSET="hysteria-linux-riscv64" ;;
    s390x) ASSET="hysteria-linux-s390x" ;;
    *) die "不支持的架构: $(uname -m)" ;;
    esac
}

detect_service_manager() {
    if [ "$NO_SERVICE" = 1 ]; then
        SVC_KIND="none"
    elif [ -d /run/systemd/system ] && has systemctl; then
        SVC_KIND="systemd"
    elif has rc-service && has rc-update; then
        SVC_KIND="openrc"
    else
        SVC_KIND="unknown"
    fi
}

port_in_use() {
    # 直接读 /proc，不依赖 ss/netstat。$2 为 udp 或 tcp。
    hex="$(printf '%04X' "$1")"
    for f in "/proc/net/$2" "/proc/net/${2}6"; do
        [ -r "$f" ] || continue
        if awk -v h=":$hex" 'NR>1 && substr($2, length($2)-4) == h {found=1} END {exit !found}' "$f"; then
            return 0
        fi
    done
    return 1
}

random_free_port() {
    n=0
    while [ "$n" -lt 50 ]; do
        r="$(od -An -N2 -tu2 /dev/urandom | tr -d ' \n')"
        p=$((20000 + r % 40001))
        if ! port_in_use "$p" "$1"; then
            echo "$p"
            return 0
        fi
        n=$((n + 1))
    done
    die "找不到空闲端口"
}

random_secret() {
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
}

detect_public_ip() {
    has curl || return 0
    for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
        ip="$(curl -4 -fsS --max-time 8 "$url" 2>/dev/null | tr -d ' \r\n' || true)"
        case "$ip" in
        *[!0-9.]* | "") ;;
        *)
            echo "$ip"
            return 0
            ;;
        esac
    done
}

ip_is_local() {
    if has ip; then
        ip -4 addr 2>/dev/null | grep -q "inet $1/"
    else
        hostname -i 2>/dev/null | grep -qw "$1"
    fi
}

latest_tag() {
    url="$(curl -fsSIL --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")" ||
        die "无法访问 GitHub，请检查网络，或用 --version 指定版本后重试"
    tag="$(printf '%s' "$url" | sed -e 's#.*/tag/##' -e 's#%2[Ff]#/#g')"
    case "$tag" in
    app/v*) echo "$tag" ;;
    *) die "无法解析最新版本: $url" ;;
    esac
}

# ---------- 安装步骤 ----------

install_packages() {
    missing=""
    has curl || missing="$missing curl"
    has openssl || missing="$missing openssl"
    [ -n "$missing" ] || return 0

    info "安装依赖:$missing"
    # shellcheck disable=SC2086
    if has apk; then
        apk add --no-cache $missing ca-certificates >/dev/null
    elif has apt-get; then
        # apt-get update 很吃内存，先尝试直接安装，失败再更新索引。
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y --no-install-recommends $missing ca-certificates >/dev/null 2>&1 || {
            apt-get update >/dev/null
            apt-get install -y --no-install-recommends $missing ca-certificates >/dev/null
        }
    elif has dnf; then
        dnf install -y $missing ca-certificates >/dev/null
    elif has yum; then
        yum install -y $missing ca-certificates >/dev/null
    else
        die "请先手动安装:$missing"
    fi
}

# /tmp 常是内存盘，文件会计入内存配额，所以必须下载到磁盘。
choose_download_dir() {
    for d in "$CONF_DIR" /var/tmp "${HOME:-/root}"; do
        mkdir -p "$d" 2>/dev/null || continue
        [ "$(stat -f -c %T "$d" 2>/dev/null || echo unknown)" != tmpfs ] || continue
        free_kb="$(df -Pk "$d" 2>/dev/null | awk 'NR==2 {print $4}')"
        [ "${free_kb:-0}" -ge 40960 ] || continue
        DL_DIR="$d/.hy2-dl.$$"
        mkdir -p "$DL_DIR"
        return 0
    done
    die "找不到至少有 40MB 空闲的非内存盘目录"
}

sha256_of() {
    sha256sum "$1" | awk '{print $1}'
}

install_binary() {
    tag="$VERSION"
    [ -n "$tag" ] || tag="$(latest_tag)"
    base="https://github.com/$REPO/releases/download/$tag"

    info "版本 $tag，文件 $ASSET"
    want="$(curl -fsSL --retry 3 --max-time 60 "$base/hashes.txt" |
        awk -v a="$ASSET" '{n=$2; sub(/^.*\//, "", n); if (n == a) print $1}')" ||
        die "无法下载校验文件 hashes.txt"
    [ -n "$want" ] || die "hashes.txt 中找不到 $ASSET"

    if [ -x "$BIN" ] && [ "$(sha256_of "$BIN")" = "$want" ]; then
        info "已是该版本，跳过下载"
        return 0
    fi

    choose_download_dir
    info "下载到 $DL_DIR（避开内存盘）"
    curl -fsSL --retry 3 --max-time 600 -o "$DL_DIR/hysteria" "$base/$ASSET" || die "下载失败"
    [ "$(sha256_of "$DL_DIR/hysteria")" = "$want" ] || die "SHA256 校验失败，已中止安装"
    info "SHA256 校验通过"

    mkdir -p "$(dirname "$BIN")"
    chmod 755 "$(dirname "$BIN")" 2>/dev/null || true
    cp "$DL_DIR/hysteria" "$BIN.new"
    chmod 755 "$BIN.new"
    # 用 mv 原子替换，服务运行中也不会遇到 text file busy。
    mv -f "$BIN.new" "$BIN"
    rm -rf "$DL_DIR"
    DL_DIR=""
}

write_cert() {
    if [ -s "$CERT_FILE" ] && [ -s "$KEY_FILE" ] && [ "${OLD_SNI:-}" = "$SNI" ]; then
        info "保留现有证书"
        return 0
    fi
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$KEY_FILE" -out "$CERT_FILE" -subj "/CN=$SNI" -days 3650 2>/dev/null ||
        die "生成证书失败"
}

render_config() {
    cat <<EOF
# 由 hy2-lowmem.sh 生成，内存档位: $PROFILE（上限 ${MEM_MB}MB）
listen: :$PORT
tls:
  cert: $CERT_FILE
  key: $KEY_FILE
auth:
  type: password
  password: $1
EOF
    if [ "$USE_OBFS" = 1 ]; then
        cat <<EOF
obfs:
  type: salamander
  salamander:
    password: $2
EOF
    fi
    cat <<EOF
quic:
  initStreamReceiveWindow: $STREAM_INIT
  maxStreamReceiveWindow: $STREAM_MAX
  initConnReceiveWindow: $CONN_INIT
  maxConnReceiveWindow: $CONN_MAX
  maxIncomingStreams: $MAX_STREAMS
udpIdleTimeout: 30s
speedTest: false
EOF
}

write_state() {
    cat >"$STATE_FILE" <<EOF
PORT='$PORT'
PUBLIC_PORT='$PUBLIC_PORT'
PUBLIC_HOST='$PUBLIC_HOST'
SNI='$SNI'
AUTH='$AUTH'
USE_OBFS='$USE_OBFS'
OBFS='$OBFS'
EOF
    chmod 600 "$STATE_FILE"
}

create_service_user() {
    id "$SVC_USER" >/dev/null 2>&1 && return 0
    if has adduser && adduser --help 2>&1 | grep -q -- ' -S'; then
        adduser -S -D -H -s /sbin/nologin "$SVC_USER" >/dev/null
    elif has useradd; then
        nologin="$(command -v nologin || echo /bin/false)"
        useradd -r -M -s "$nologin" "$SVC_USER"
    else
        die "无法创建服务用户 $SVC_USER"
    fi
}

write_systemd_unit() {
    umask 022
    cat >"/etc/systemd/system/$SVC_NAME.service" <<EOF
[Unit]
Description=Hysteria2 server (hy2-lowmem, profile $PROFILE)
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
Environment=GOMEMLIMIT=${GOMEM_MB}MiB
Environment=GOGC=$GOGC_VALUE
Environment=HYSTERIA_LOG_LEVEL=warn
Environment=HYSTERIA_DISABLE_UPDATE_CHECK=1
ExecStart=$BIN server --config $CONF_FILE
Restart=always
RestartSec=3
LimitNOFILE=65535
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    umask 077
    systemctl daemon-reload
    systemctl enable "$SVC_NAME" >/dev/null 2>&1
    systemctl restart "$SVC_NAME"
}

write_openrc_script() {
    if has supervise-daemon; then
        sup='supervisor=supervise-daemon
respawn_delay=3
respawn_max=0'
    else
        warn "没有 supervise-daemon，进程崩溃后不会自动重启"
        sup='command_background=true
pidfile="/run/${RC_SVCNAME}.pid"'
    fi
    umask 022
    cat >"/etc/init.d/$SVC_NAME" <<EOF
#!/sbin/openrc-run
name="$SVC_NAME"
description="Hysteria2 server (hy2-lowmem, profile $PROFILE)"
command="$BIN"
command_args="server --config $CONF_FILE"
command_user="$SVC_USER:$SVC_USER"
$sup
output_log="$LOG_FILE"
error_log="$LOG_FILE"
export GOMEMLIMIT=${GOMEM_MB}MiB
export GOGC=$GOGC_VALUE
export HYSTERIA_LOG_LEVEL=warn
export HYSTERIA_DISABLE_UPDATE_CHECK=1

depend() {
    after net firewall
}

start_pre() {
    checkpath -f -o $SVC_USER:$SVC_USER -m 640 "$LOG_FILE"
    # 日志超过 1MB 时清空，避免占满小磁盘
    if [ "\$(wc -c <"$LOG_FILE")" -gt 1048576 ]; then
        : >"$LOG_FILE"
    fi
}
EOF
    chmod 755 "/etc/init.d/$SVC_NAME"
    umask 077
    rc-update add "$SVC_NAME" default >/dev/null 2>&1 || true
    rc-service "$SVC_NAME" stop >/dev/null 2>&1 || true
    rc-service "$SVC_NAME" start >/dev/null 2>&1 || die "服务启动失败，查看 $LOG_FILE"
}

open_firewall() {
    if has ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
        ufw allow "$PORT/udp" >/dev/null && info "ufw 已放行 $PORT/udp"
    elif has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="$PORT/udp" >/dev/null &&
            firewall-cmd --reload >/dev/null && info "firewalld 已放行 $PORT/udp"
    fi
}

service_is_running() {
    case "$SVC_KIND" in
    systemd) systemctl is-active --quiet "$SVC_NAME" ;;
    openrc) rc-service "$SVC_NAME" status >/dev/null 2>&1 ;;
    *) return 1 ;;
    esac
}

mask_secrets() {
    sed -E 's/[0-9a-f]{32}/<hidden>/g' | tail -n "$1" | cut -c1-200
}

# 本机起一个真实客户端连服务端，走 SOCKS5 发请求，验证配置和代理链路。
# 它不能证明外网可达：NAT 映射需要从外部连接才能确认。
self_test() {
    TEST_CFG="$CONF_DIR/.selftest.yaml"
    TEST_SRV_LOG="$CONF_DIR/.selftest-server.log"
    TEST_CLI_LOG="$CONF_DIR/.selftest-client.log"
    socks="$(random_free_port tcp)"

    if [ "$SVC_KIND" = none ]; then
        GOMEMLIMIT="${GOMEM_MB}MiB" GOGC="$GOGC_VALUE" HYSTERIA_DISABLE_UPDATE_CHECK=1 \
            "$BIN" server --config "$CONF_FILE" >"$TEST_SRV_LOG" 2>&1 &
        SERVER_PID=$!
    fi

    {
        echo "server: 127.0.0.1:$PORT"
        echo "auth: $AUTH"
        if [ "$USE_OBFS" = 1 ]; then
            printf 'obfs:\n  type: salamander\n  salamander:\n    password: %s\n' "$OBFS"
        fi
        printf 'tls:\n  sni: %s\n  insecure: true\n' "$SNI"
        printf 'socks5:\n  listen: 127.0.0.1:%s\n' "$socks"
    } >"$TEST_CFG"

    sleep 2
    GOMEMLIMIT=15MiB GOGC=50 HYSTERIA_DISABLE_UPDATE_CHECK=1 \
        "$BIN" client --config "$TEST_CFG" >"$TEST_CLI_LOG" 2>&1 &
    CLIENT_PID=$!

    ok=0
    n=0
    while [ "$n" -lt 5 ]; do
        sleep 2
        code="$(curl -4 -s --max-time 8 -o /dev/null -w '%{http_code}' \
            --socks5-hostname "127.0.0.1:$socks" https://www.gstatic.com/generate_204 || true)"
        if [ "$code" = 204 ]; then
            ok=1
            break
        fi
        n=$((n + 1))
    done

    if [ "$ok" = 1 ]; then
        info "自检通过: 客户端已连上服务端，代理请求返回 204"
    else
        warn "自检失败（可能是服务端问题，也可能是本机访问不了 gstatic.com）"
        [ ! -s "$TEST_CLI_LOG" ] || mask_secrets 5 <"$TEST_CLI_LOG" >&2
        [ ! -s "$TEST_SRV_LOG" ] || mask_secrets 5 <"$TEST_SRV_LOG" >&2
    fi
    stop_test_processes
    rm -f "$TEST_CFG" "$TEST_SRV_LOG" "$TEST_CLI_LOG"
    [ "$ok" = 1 ]
}

stop_test_processes() {
    for pid in "$CLIENT_PID" "$SERVER_PID"; do
        [ -n "$pid" ] || continue
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    CLIENT_PID=""
    SERVER_PID=""
}

cleanup() {
    rc=$?
    stop_test_processes
    [ -z "$DL_DIR" ] || rm -rf "$DL_DIR"
    if [ -n "$TEST_CFG" ]; then
        rm -f "$TEST_CFG" "$TEST_SRV_LOG" "$TEST_CLI_LOG"
    fi
    exit "$rc"
}

# ---------- 输出 ----------

share_link() {
    case "$PUBLIC_HOST" in
    *:*) host="[$PUBLIC_HOST]" ;;
    *) host="$PUBLIC_HOST" ;;
    esac
    pin="$(openssl x509 -in "$CERT_FILE" -noout -fingerprint -sha256 |
        cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f')"
    q="insecure=1&pinSHA256=$pin"
    if [ "$USE_OBFS" = 1 ]; then
        q="$q&obfs=salamander&obfs-password=$OBFS"
    fi
    q="$q&sni=$SNI"
    echo "hysteria2://$AUTH@$host:$PUBLIC_PORT/?$q#hy2-$PUBLIC_HOST"
}

print_result() {
    echo
    echo "==================== 分享链接（等同密码，请勿公开）===================="
    share_link
    echo "======================================================================="
    echo "内部监听: UDP $PORT    对外端口: UDP $PUBLIC_PORT"
    echo "内存档位: $PROFILE（上限 ${MEM_MB}MB，GOMEMLIMIT ${GOMEM_MB}MiB）"
    echo "配置文件: $CONF_FILE"
}

# ---------- 命令 ----------

cmd_show() {
    [ -r "$STATE_FILE" ] || die "找不到 $STATE_FILE，该机器可能不是用本脚本配置的"
    # shellcheck disable=SC1090
    . "$STATE_FILE"
    share_link
}

cmd_status() {
    detect_service_manager
    case "$SVC_KIND" in
    systemd) systemctl --no-pager status "$SVC_NAME" | head -n 6 || true ;;
    openrc) rc-service "$SVC_NAME" status || true ;;
    *) info "未检测到服务管理器" ;;
    esac
    pid="$(pidof hysteria 2>/dev/null || true)"
    for p in $pid; do
        awk -v p="$p" '/^VmRSS:/ {printf "[hy2] 进程 %s 内存: %d MB\n", p, $2/1024}' "/proc/$p/status" 2>/dev/null || true
    done
    if [ -r /sys/fs/cgroup/memory.events ]; then
        info "cgroup 内存限制: $(cat /sys/fs/cgroup/memory.max 2>/dev/null)"
        info "$(grep '^oom_kill ' /sys/fs/cgroup/memory.events || true)"
    fi
    if [ -s "$LOG_FILE" ]; then
        info "最近日志:"
        mask_secrets 5 <"$LOG_FILE"
    fi
}

cmd_uninstall() {
    [ "$(id -u)" = 0 ] || [ -n "$PREFIX" ] || die "请用 root 运行"
    detect_service_manager
    [ -e "$CONF_DIR" ] || [ -e "$BIN" ] || die "没有发现已安装的 Hysteria"

    echo "将删除: $BIN $CONF_DIR $LOG_FILE，以及服务 $SVC_NAME"
    if [ "$ASSUME_YES" != 1 ]; then
        [ -r /dev/tty ] || die "无法确认，请加 --yes"
        printf '确认卸载？输入 yes 继续: ' >/dev/tty
        read -r answer </dev/tty
        [ "$answer" = yes ] || die "已取消"
    fi

    old_port=""
    if [ -r "$STATE_FILE" ]; then
        old_port="$(sed -n "s/^PORT='\(.*\)'$/\1/p" "$STATE_FILE")"
    fi

    case "$SVC_KIND" in
    systemd)
        systemctl disable --now "$SVC_NAME" >/dev/null 2>&1 || true
        rm -f "/etc/systemd/system/$SVC_NAME.service"
        systemctl daemon-reload
        ;;
    openrc)
        rc-service "$SVC_NAME" stop >/dev/null 2>&1 || true
        rc-update del "$SVC_NAME" default >/dev/null 2>&1 || true
        rm -f "/etc/init.d/$SVC_NAME"
        ;;
    esac
    rm -rf "$CONF_DIR"
    rm -f "$BIN" "$LOG_FILE"

    if [ -z "$PREFIX" ]; then
        if id "$SVC_USER" >/dev/null 2>&1; then
            if has deluser; then
                deluser "$SVC_USER" >/dev/null 2>&1 || true
            elif has userdel; then
                userdel "$SVC_USER" >/dev/null 2>&1 || true
            fi
        fi
        if [ -n "$old_port" ]; then
            if has ufw && ufw status 2>/dev/null | grep -q '^Status: active'; then
                ufw delete allow "$old_port/udp" >/dev/null 2>&1 || true
            elif has firewall-cmd && firewall-cmd --state >/dev/null 2>&1; then
                firewall-cmd --permanent --remove-port="$old_port/udp" >/dev/null 2>&1 || true
                firewall-cmd --reload >/dev/null 2>&1 || true
            fi
        fi
    fi
    info "已卸载"
}

cmd_install() {
    [ "$(id -u)" = 0 ] || [ -n "$PREFIX" ] || die "请用 root 运行（或用 --prefix 安装到自有目录）"
    [ "$(uname -s)" = Linux ] || die "只支持 Linux"

    # 记下命令行指定的值，它们优先于已保存的状态。
    arg_port="$PORT" arg_pub_port="$PUBLIC_PORT" arg_pub_host="$PUBLIC_HOST"
    arg_sni="$SNI" arg_auth="$AUTH" arg_obfs="$OBFS" arg_use_obfs="$USE_OBFS"

    if [ -r "$STATE_FILE" ] && [ "$RECONFIGURE" != 1 ] && [ "$DRY_RUN" != 1 ]; then
        info "已经配置过；如需修改请加 --reconfigure。当前分享链接:"
        cmd_show
        return 0
    fi
    if [ -e "$CONF_FILE" ] && [ ! -r "$STATE_FILE" ] && [ "$RECONFIGURE" != 1 ] && [ "$DRY_RUN" != 1 ]; then
        die "$CONF_FILE 已存在但不是本脚本生成的。加 --reconfigure 才会覆盖（会生成新密码，除非用选项指定）"
    fi

    OLD_SNI=""
    OLD_PORT=""
    if [ -r "$STATE_FILE" ]; then
        # shellcheck disable=SC1090
        . "$STATE_FILE"
        OLD_SNI="$SNI"
        OLD_PORT="$PORT"
    fi
    PORT="${arg_port:-$PORT}"
    PUBLIC_HOST="${arg_pub_host:-$PUBLIC_HOST}"
    SNI="${arg_sni:-${SNI:-www.bing.com}}"
    AUTH="${arg_auth:-$AUTH}"
    OBFS="${arg_obfs:-$OBFS}"
    USE_OBFS="${arg_use_obfs:-${USE_OBFS:-1}}"
    # 内部端口改了而对外端口没指定时，对外端口跟随内部端口。
    if [ -n "$arg_pub_port" ]; then
        PUBLIC_PORT="$arg_pub_port"
    elif [ -n "$arg_port" ]; then
        PUBLIC_PORT="$arg_port"
    fi

    detect_service_manager
    if [ "$SVC_KIND" = unknown ]; then
        die "没有检测到 systemd 或 OpenRC。无 init 的容器请加 --no-service，并自行启动进程"
    fi
    detect_asset
    mem="$(detect_mem_mb)"
    select_profile "$mem"
    [ "$MEM_MB" -ge 48 ] || warn "内存只有 ${MEM_MB}MB，低于建议的 48MB，hy2 可能反复被杀"

    # 重新配置时，原端口可能正被运行中的服务自己占用，这种情况不算冲突。
    if [ -z "$PORT" ]; then
        PORT="$(random_free_port udp)"
    elif port_in_use "$PORT" udp; then
        if [ "$PORT" != "$OLD_PORT" ] || ! service_is_running; then
            die "UDP 端口 $PORT 已被占用"
        fi
    fi
    PUBLIC_PORT="${PUBLIC_PORT:-$PORT}"
    [ -n "$PUBLIC_HOST" ] || PUBLIC_HOST="$(detect_public_ip || true)"

    NAT_NOTE=""
    if [ -n "$PUBLIC_HOST" ] && [ -z "$arg_pub_host" ] && ! ip_is_local "$PUBLIC_HOST"; then
        NAT_NOTE=1
    fi

    if [ "$DRY_RUN" = 1 ]; then
        echo "--- 检测结果（dry-run，未做改动）"
        echo "架构文件: $ASSET"
        echo "服务管理: $SVC_KIND"
        echo "内存上限: ${MEM_MB}MB -> 档位 $PROFILE，GOMEMLIMIT ${GOMEM_MB}MiB，GOGC $GOGC_VALUE"
        echo "公网地址: ${PUBLIC_HOST:-未检测到}$([ -n "$NAT_NOTE" ] && echo '（NAT，需端口映射）')"
        echo "监听端口: UDP $PORT，对外 UDP $PUBLIC_PORT"
        echo "下载目录: 非内存盘（$CONF_DIR 优先）"
        echo "--- 将写入的配置（密码已隐藏）"
        render_config '<hidden>' '<hidden>'
        return 0
    fi

    [ -n "$AUTH" ] || AUTH="$(random_secret)"
    if [ "$USE_OBFS" = 1 ]; then
        [ -n "$OBFS" ] || OBFS="$(random_secret)"
    else
        OBFS=""
    fi

    install_packages
    [ -n "$PUBLIC_HOST" ] || PUBLIC_HOST="$(detect_public_ip || true)"
    [ -n "$PUBLIC_HOST" ] || die "检测不到公网地址，请用 --public-host 指定"

    mkdir -p "$CONF_DIR"
    install_binary
    write_cert
    render_config "$AUTH" "$OBFS" >"$CONF_FILE"
    write_state

    case "$SVC_KIND" in
    systemd | openrc)
        mkdir -p "$(dirname "$LOG_FILE")"
        create_service_user
        chown -R "$SVC_USER:$SVC_USER" "$CONF_DIR"
        chmod 750 "$CONF_DIR"
        if [ "$SVC_KIND" = systemd ]; then
            write_systemd_unit
        else
            write_openrc_script
        fi
        open_firewall
        sleep 2
        service_is_running || die "服务没有运行，请运行 sh $0 status 查看原因"
        info "服务已启动并设为开机自启"
        ;;
    esac

    test_failed=0
    if [ "$NO_TEST" != 1 ]; then
        self_test || test_failed=1
    fi

    print_result
    if [ -n "$NAT_NOTE" ]; then
        echo
        warn "这台机器在 NAT 后面（公网 $PUBLIC_HOST 不在本机网卡上）。"
        warn "请确认服务商已把外部 UDP $PUBLIC_PORT 映射到内部 UDP $PORT，否则客户端连不上。"
    fi
    if [ "$SVC_KIND" = none ]; then
        echo
        info "没有注册服务，请自行启动:"
        echo "GOMEMLIMIT=${GOMEM_MB}MiB GOGC=$GOGC_VALUE $BIN server --config $CONF_FILE"
    fi
    [ "$test_failed" = 0 ] || exit 1
}

main() {
    parse_args "$@"
    set_paths
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    case "$CMD" in
    install) cmd_install ;;
    show) cmd_show ;;
    status) cmd_status ;;
    uninstall) cmd_uninstall ;;
    esac
}

main "$@"
