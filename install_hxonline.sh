#!/bin/bash
# 强制使用 Bash 运行本脚本
if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi
set -e

# ============ 颜色定义 ============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============ Logo ============
clear
echo -e "${CYAN}"
echo "  ██╗      ███████╗"
echo "  ██║      ██╔════╝"
echo "  ██║      █████╗  "
echo "  ██║      ██╔══╝  "
echo "  ███████╗ ██║     "
echo "  ╚══════╝ ╚═╝     "
echo -e "${NC}"
echo -e "${BOLD}${GREEN}    幻想纹章Next后端一键部署脚本${NC}"
echo ""

# ========== 权限检查 ==========
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}错误：请以 root 身份运行此脚本。${NC}"
    echo -e "可以执行： ${YELLOW}sudo su -${NC}  切换到 root 后再运行本脚本。"
    exit 1
fi

# ========== 一、配置确认区域 ==========
echo -e "${BOLD}${YELLOW}请完成以下配置，所有选项确认后才会开始安装。${NC}"
echo ""

# 1. 同意声明
echo -e "${CYAN}============================================${NC}"
echo -e "${BOLD}  使用协议与免责声明${NC}"
echo -e "${CYAN}============================================${NC}"
echo "本脚本将下载并安装幻想纹章Next游戏后端，"
echo "包括但不限于：停止占用端口的进程、下载二进制文件、"
echo "注册系统服务、设置定时任务等。请确保您有权操作本服务器。"
echo "继续安装即表示您同意相关条款并自行承担所有风险。"
echo ""
echo -n -e "${BOLD}是否同意并继续？(y/n): ${NC}"
read AGREEMENT
if [[ "${AGREEMENT,,}" != "y" ]]; then
    echo -e "${RED}已取消安装。${NC}"
    exit 0
fi

# 2. 自定义安装目录
echo ""
echo -n -e "${CYAN}请输入安装目录（默认 /mnt/hxonline）: ${NC}"
read INPUT_DIR
if [ -z "$INPUT_DIR" ]; then
    WORK_DIR="/mnt/hxonline"
else
    WORK_DIR="$INPUT_DIR"
fi
echo -e "${GREEN}安装目录：${WORK_DIR}${NC}"

# 3. 端口号（支持默认 12345）
while true; do
    echo ""
    echo -n -e "${CYAN}请输入后端服务端口号（默认 12345）: ${NC}"
    read PORT
    if [ -z "$PORT" ]; then
        PORT=12345
        echo -e "${GREEN}使用默认端口：${PORT}${NC}"
        break
    elif [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    else
        echo -e "${RED}无效端口，请输入 1-65535 之间的数字。${NC}"
    fi
done
echo -e "${GREEN}服务端口：${PORT}${NC}"

# 4. 是否注册为系统服务（开机自启）
USE_SYSTEMD=false
if command -v systemctl &> /dev/null; then
    echo ""
    echo -n -e "${CYAN}是否注册为系统服务并开机自启？(y/n): ${NC}"
    read ENABLE_SERVICE
    if [[ "${ENABLE_SERVICE,,}" =~ ^[y] ]]; then
        USE_SYSTEMD=true
        echo -e "${GREEN}已选择：注册系统服务${NC}"
    else
        echo -e "${YELLOW}已选择：不注册服务，仅使用 nohup 方式运行${NC}"
    fi
else
    echo -e "${YELLOW}当前系统未安装 systemd，将只能使用 nohup 方式运行。${NC}"
fi

# 5. 是否每日定时重启
CRON_ENABLED=false
CRON_TIME="04:00"
echo ""
echo -n -e "${CYAN}是否开启每日定时重启后端？(y/n): ${NC}"
read ENABLE_CRON
if [[ "${ENABLE_CRON,,}" =~ ^[y] ]]; then
    CRON_ENABLED=true
    while true; do
        echo -n -e "${CYAN}请输入每天重启的时间（格式 HH:MM，例如 04:00）: ${NC}"
        read CRON_TIME
        if [[ "$CRON_TIME" =~ ^[0-2][0-9]:[0-5][0-9]$ ]]; then
            break
        else
            echo -e "${RED}时间格式错误，请使用 HH:MM（如 04:00）${NC}"
        fi
    done
    echo -e "${GREEN}已设置每日 ${CRON_TIME} 自动重启后端。${NC}"
else
    echo -e "${YELLOW}未开启定时重启。${NC}"
fi

# ========== 最终确认 ==========
echo ""
echo -e "${BOLD}${YELLOW}------------------------------------------${NC}"
echo -e "${BOLD}配置汇总：${NC}"
echo -e "  安装目录：${WORK_DIR}"
echo -e "  服务端口：${PORT}"
echo -e "  开机自启：$($USE_SYSTEMD && echo '是' || echo '否')"
echo -e "  定时重启：$($CRON_ENABLED && echo "是，每天 ${CRON_TIME}" || echo '否')"
echo -e "${BOLD}${YELLOW}------------------------------------------${NC}"
echo ""
echo -n -e "${BOLD}确认以上配置并开始安装？(y/n): ${NC}"
read FINAL_CONFIRM
if [[ "${FINAL_CONFIRM,,}" != "y" ]]; then
    echo -e "${RED}已取消安装。${NC}"
    exit 0
fi

# ========== 二、开始安装 ==========
echo ""
echo -e "${BOLD}${YELLOW}开始安装...${NC}"

MAIN_URL="https://gitee.com/lingfeng6/install_hxonline/releases/download/1.0/hxonline"
BACKUP_URL="https://github.com/bylingfeng/install_hxonline/releases/download/HXWZ-Next/hxonline"
DOWNLOAD_PATH="$WORK_DIR/hxonline"
MAX_RETRY=3
RETRY_DELAY=3
CMD="$WORK_DIR/hxonline --wss 0 --model=product --port $PORT"
LOG_FILE="$WORK_DIR/console.log"

log() {
    echo -e "${GREEN}[$(date)]${NC} $1"
}

mkdir -p "$WORK_DIR"

# 端口清理（兼容所有发行版）
if ! command -v timeout &> /dev/null; then
    timeout() {
        local seconds=$1
        shift
        "$@" &
        local pid=$!
        ( sleep "$seconds"; kill -9 "$pid" 2>/dev/null ) &
        wait "$pid" 2>/dev/null
        return $?
    }
fi

echo -e "${BOLD}${YELLOW}=== 清理端口 $PORT ===${NC}"

cleanup_port() {
    local port=$1
    if command -v lsof &> /dev/null; then
        local pids=$(timeout 5 lsof -ti :"$port" 2>/dev/null) || true
        if [ -n "$pids" ]; then
            echo -e "${YELLOW}发现占用进程 PID: $pids (via lsof)，正在终止...${NC}"
            kill -9 $pids 2>/dev/null || true
            sleep 1
            return 0
        fi
    fi
    if command -v ss &> /dev/null; then
        local pids=$(timeout 5 ss -tlnp "sport = :$port" 2>/dev/null | grep -Po 'pid=\K[0-9]+') || true
        if [ -n "$pids" ]; then
            echo -e "${YELLOW}发现占用进程 PID: $pids (via ss)，正在终止...${NC}"
            kill -9 $pids 2>/dev/null || true
            sleep 1
            return 0
        fi
    fi
    if command -v fuser &> /dev/null; then
        if timeout 5 fuser -k -KILL ${port}/tcp 2>/dev/null; then
            sleep 1
            return 0
        fi
    fi
    if [ -f /proc/net/tcp ]; then
        local inode=$(awk -v port="$(printf '%04X' "$port")" '$2 ~ /:'"$port"'$/{print $10}' /proc/net/tcp 2>/dev/null | head -1)
        if [ -n "$inode" ]; then
            local pid=$(find /proc/[0-9]*/fd -lname "socket:\[$inode\]" 2>/dev/null | cut -d/ -f3 | head -1)
            if [ -n "$pid" ]; then
                echo -e "${YELLOW}发现占用进程 PID: $pid (via /proc)，正在终止...${NC}"
                kill -9 "$pid" 2>/dev/null || true
                sleep 1
                return 0
            fi
        fi
    fi
    return 1
}

cleanup_port "$PORT" || echo -e "${YELLOW}未找到可用的端口检查工具，跳过端口清理。${NC}"

# 二次确认端口释放
echo -e "${CYAN}验证端口 $PORT 是否已释放...${NC}"
if command -v lsof &> /dev/null; then
    REMAIN=$(timeout 5 lsof -ti :"$PORT" 2>/dev/null) || true
elif command -v ss &> /dev/null; then
    REMAIN=$(timeout 5 ss -tlnp "sport = :$PORT" 2>/dev/null | grep -q ":$PORT" && echo "1") || true
elif command -v fuser &> /dev/null; then
    REMAIN=$(timeout 5 fuser ${PORT}/tcp 2>/dev/null) || true
else
    REMAIN=""
fi

if [ -n "$REMAIN" ]; then
    echo -e "${RED}失败：端口 $PORT 仍被占用，无法继续。${NC}"
    exit 1
fi
echo -e "${GREEN}端口 $PORT 已释放。${NC}"

pkill -9 -f "$CMD" 2>/dev/null || true
sleep 1
echo -e "${GREEN}同名进程清理完成。${NC}"
rm -f "$WORK_DIR/hxonline.pid"

# 磁盘空间检查
AVAIL=$(df -m "$WORK_DIR" 2>/dev/null | tail -1 | awk '{print $4}')
if [ -n "$AVAIL" ] && [ "$AVAIL" -lt 50 ]; then
    echo -e "${RED}失败：磁盘空间不足，${WORK_DIR} 所在分区仅剩 ${AVAIL}MB，需要至少 50MB。${NC}"
    exit 1
fi

# 下载函数
download_file() {
    local url="$1"
    local output="$2"
    rm -f "$output"
    if [ -t 1 ]; then
        echo -e "${CYAN}下载地址：${NC}$url"
        if command -v curl &> /dev/null; then
            curl -fL --progress-bar "$url" -o "$output"
        elif command -v wget &> /dev/null; then
            wget --show-progress "$url" -O "$output"
        else
            echo -e "${RED}错误：系统中未找到 curl 或 wget，无法下载文件。${NC}"
            exit 1
        fi
    else
        if command -v curl &> /dev/null; then
            curl -fsSL "$url" -o "$output"
        elif command -v wget &> /dev/null; then
            wget -q "$url" -O "$output"
        else
            echo -e "${RED}错误：系统中未找到 curl 或 wget，无法下载文件。${NC}"
            exit 1
        fi
    fi
    return $?
}

echo -e "${BOLD}${YELLOW}正在从主地址下载 hxonline ...${NC}"
if download_file "$MAIN_URL" "$DOWNLOAD_PATH"; then
    DOWNLOADED_URL="$MAIN_URL"
    echo -e "${GREEN}主地址下载成功。${NC}"
else
    echo -e "${YELLOW}主地址下载失败，切换备用地址...${NC}"
    rm -f "$DOWNLOAD_PATH"
    if download_file "$BACKUP_URL" "$DOWNLOAD_PATH"; then
        DOWNLOADED_URL="$BACKUP_URL"
        echo -e "${GREEN}备用地址下载成功。${NC}"
    else
        echo -e "${RED}错误：备用地址下载也失败，部署中止。${NC}"
        exit 1
    fi
fi

# SHA256 校验
SHA256_URL="${DOWNLOADED_URL}.sha256"
echo -e "${CYAN}尝试下载校验文件 $SHA256_URL ...${NC}"
SHA256_FILE=$(mktemp)
if download_file "$SHA256_URL" "$SHA256_FILE"; then
    EXPECTED_HASH=$(awk '{print $1}' "$SHA256_FILE" | head -1)
    ACTUAL_HASH=$(sha256sum "$DOWNLOAD_PATH" | awk '{print $1}')
    if [ "$EXPECTED_HASH" = "$ACTUAL_HASH" ]; then
        echo -e "${GREEN}SHA256 校验通过。${NC}"
    else
        echo -e "${RED}错误：SHA256 校验失败，文件可能已损坏或被篡改。${NC}"
        rm -f "$SHA256_FILE"
        exit 1
    fi
    rm -f "$SHA256_FILE"
else
    echo -e "${YELLOW}未找到校验文件，跳过完整性校验。${NC}"
fi

chmod +x "$DOWNLOAD_PATH"
echo -e "${GREEN}已赋予可执行权限。${NC}"

# 日志大小控制（提前检查）
if [ -f "$LOG_FILE" ]; then
    SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 10485760 ]; then
        mv "$LOG_FILE" "$LOG_FILE.old"
        echo -e "${YELLOW}日志文件已超过 10MB，已备份为 $LOG_FILE.old。${NC}"
    fi
fi

# 启动服务（根据前面选择）
start_nohup() {
    log "正在启动 hxonline (nohup)..."
    cd "$WORK_DIR" || { log "失败：无法进入目录 $WORK_DIR"; return 1; }
    nohup $CMD >> "$LOG_FILE" 2>&1 &
    START_PID=$!
    sleep 2
    if kill -0 $START_PID 2>/dev/null; then
        log "成功：hxonline 已启动，PID = $START_PID"
        return 0
    else
        log "失败：hxonline 未能启动。"
        if [ -f "$LOG_FILE" ]; then
            log "最后 5 行程序日志："
            tail -5 "$LOG_FILE"
        fi
        return 1
    fi
}

if $USE_SYSTEMD; then
    SERVICE_FILE="/etc/systemd/system/hxonline.service"
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=HXOnline Game Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$WORK_DIR
ExecStart=$CMD
Restart=on-failure
RestartSec=5
StartLimitBurst=10
StartLimitIntervalSec=60
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="LD_LIBRARY_PATH=/usr/local/lib:/usr/lib"

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable hxonline
    echo -e "${GREEN}系统服务文件已生成并启用。${NC}"
    if systemctl start hxonline; then
        echo -e "${GREEN}systemd 服务启动成功！${NC}"
    else
        echo -e "${RED}systemd 启动失败，回退到 nohup 方式...${NC}"
        start_nohup
    fi
else
    echo -e "${BOLD}${YELLOW}=== 使用 nohup 模式启动 ===${NC}"
    RETRY=0
    while [ $RETRY -lt $MAX_RETRY ]; do
        if start_nohup; then
            break
        fi
        RETRY=$((RETRY+1))
        if [ $RETRY -lt $MAX_RETRY ]; then
            echo -e "${YELLOW}将在 ${RETRY_DELAY} 秒后重试（第 $RETRY/$MAX_RETRY 次）...${NC}"
            sleep $RETRY_DELAY
        fi
    done
    if [ $RETRY -eq $MAX_RETRY ]; then
        echo -e "${RED}失败：已重试 $MAX_RETRY 次，hxonline 仍无法启动。${NC}"
        exit 1
    fi
fi

# 定时重启配置
if $CRON_ENABLED; then
    echo ""
    echo -e "${CYAN}正在配置每日定时重启...${NC}"
    HOUR=$(echo $CRON_TIME | cut -d: -f1)
    MINUTE=$(echo $CRON_TIME | cut -d: -f2)
    CRON_JOB="$MINUTE $HOUR * * * /usr/bin/systemctl restart hxonline 2>/dev/null || pkill -9 -f '$CMD' && cd $WORK_DIR && nohup $CMD >> $LOG_FILE 2>&1 &"
    (crontab -l 2>/dev/null | grep -v "hxonline" ; echo "$CRON_JOB") | crontab -
    echo -e "${GREEN}已添加定时重启任务：每天 ${CRON_TIME} 自动重启后端。${NC}"
fi

# 获取公网 IP
get_public_ip() {
    local ip=""
    local services=(
        "http://ipinfo.io/ip"
        "http://ifconfig.me"
        "http://icanhazip.com"
        "http://api.ipify.org"
        "http://checkip.amazonaws.com"
        "http://ifconfig.co"
    )
    for url in "${services[@]}"; do
        if command -v curl &> /dev/null; then
            ip=$(timeout 3 curl -s "$url" 2>/dev/null) || continue
        elif command -v wget &> /dev/null; then
            ip=$(timeout 3 wget -qO- "$url" 2>/dev/null) || continue
        fi
        if echo "$ip" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "$ip"
            return 0
        fi
    done
    ip=$(timeout 3 ip -4 addr show scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    if [ -n "$ip" ]; then
        echo "$ip"
        return 0
    fi
    return 1
}

SERVER_IP=$(get_public_ip)
if [ -z "$SERVER_IP" ]; then
    echo -e "${YELLOW}警告：自动获取公网 IP 失败。${NC}"
    echo -n -e "${CYAN}请手动输入服务器的公网 IP 地址（留空使用内网地址）: ${NC}"
    read SERVER_IP
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        [ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"
        echo -e "${YELLOW}已回退使用内网地址。${NC}"
    fi
fi

echo ""
echo -e "${BOLD}${GREEN}=========================================="
echo "  游戏后端安装成功！"
echo -e "==========================================${NC}"
echo -e "${CYAN}验证地址：${NC}http://${SERVER_IP}:${PORT}/hello"
echo -e "${CYAN}联机地址：${NC}ws://${SERVER_IP}:${PORT}"
echo -e "${CYAN}安装目录：${NC}$WORK_DIR"
echo -e "${CYAN}日志文件：${NC}$LOG_FILE"
echo -e "${YELLOW}如果无法访问请检查防火墙是否已开放端口 ${PORT}。${NC}"
if $CRON_ENABLED; then
    echo -e "${CYAN}定时重启：${NC}每天 ${CRON_TIME} 执行"
fi
echo ""
