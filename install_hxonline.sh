#!/bin/bash
set -e

# ========== 1. 权限检查 ==========
if [[ $EUID -ne 0 ]]; then
    echo "错误：请以 root 身份运行此脚本。"
    echo "可以执行： sudo su -  切换到 root 后再运行本脚本。"
    exit 1
fi

# ========== 2. 端口输入 ==========
while true; do
    read -p "请输入游戏后端要映射的端口号（例如 6666）: " PORT
    if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
        break
    else
        echo "无效端口，请输入 1-65535 之间的数字。"
    fi
done

# ========== 基本变量 ==========
WORK_DIR="/mnt/hxonline"
MAIN_URL="https://gitee.com/lingfeng6/install_hxonline/releases/download/1.0/hxonline"
BACKUP_URL="https://github.com/bylingfeng/install_hxonline/releases/download/HXWZ-Next/hxonline"
DOWNLOAD_PATH="$WORK_DIR/hxonline"
MAX_RETRY=3
RETRY_DELAY=3

mkdir -p "$WORK_DIR"

# ========== 3. 下载函数（带进度条、覆盖、智能静默） ==========
download_file() {
    local url="$1"
    local output="$2"
    rm -f "$output"

    if [ -t 1 ]; then
        echo "下载地址：$url"
        if command -v curl &> /dev/null; then
            curl -fL --progress-bar "$url" -o "$output"
        elif command -v wget &> /dev/null; then
            wget --show-progress "$url" -O "$output"
        else
            echo "错误：系统中未找到 curl 或 wget，无法下载文件。"
            exit 1
        fi
    else
        if command -v curl &> /dev/null; then
            curl -fsSL "$url" -o "$output"
        elif command -v wget &> /dev/null; then
            wget -q "$url" -O "$output"
        else
            echo "错误：系统中未找到 curl 或 wget，无法下载文件。"
            exit 1
        fi
    fi
    return $?
}

echo "正在从主地址下载 hxonline ..."
if download_file "$MAIN_URL" "$DOWNLOAD_PATH"; then
    echo "主地址下载成功。"
else
    echo "主地址下载失败，切换备用地址..."
    rm -f "$DOWNLOAD_PATH"
    if download_file "$BACKUP_URL" "$DOWNLOAD_PATH"; then
        echo "备用地址下载成功。"
    else
        echo "错误：备用地址下载也失败，部署中止。"
        exit 1
    fi
fi

chmod +x "$DOWNLOAD_PATH"
echo "已赋予可执行权限。"

# ========== 4. 通用端口清理（兼容所有发行版） ==========
CMD="./hxonline --wss 0 --model=product --port $PORT"
LOG_FILE="$WORK_DIR/console.log"

log() {
    echo "[$(date)] $1"
}

log "=== 开始启动 hxonline（root 模式） ==="

# 超时命令兼容（部分系统默认没有 timeout）
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

log "正在清理端口 $PORT 上的占用进程..."

cleanup_port() {
    local port=$1

    # 方法1：lsof
    if command -v lsof &> /dev/null; then
        local pids=$(timeout 5 lsof -ti :"$port" 2>/dev/null) || true
        if [ -n "$pids" ]; then
            echo "发现占用进程 PID: $pids (via lsof)，正在终止..."
            kill -9 $pids 2>/dev/null || true
            sleep 1
            return 0
        fi
    fi

    # 方法2：ss
    if command -v ss &> /dev/null; then
        local pids=$(timeout 5 ss -tlnp "sport = :$port" 2>/dev/null | grep -Po 'pid=\K[0-9]+') || true
        if [ -n "$pids" ]; then
            echo "发现占用进程 PID: $pids (via ss)，正在终止..."
            kill -9 $pids 2>/dev/null || true
            sleep 1
            return 0
        fi
    fi

    # 方法3：fuser
    if command -v fuser &> /dev/null; then
        if timeout 5 fuser -k -KILL ${port}/tcp 2>/dev/null; then
            sleep 1
            return 0
        fi
    fi

    # 方法4：解析 /proc/net/tcp（终极 fallback）
    if [ -f /proc/net/tcp ]; then
        local inode=$(awk -v port="$(printf '%04X' "$port")" '$2 ~ /:'"$port"'$/{print $10}' /proc/net/tcp 2>/dev/null | head -1)
        if [ -n "$inode" ]; then
            local pid=$(find /proc/[0-9]*/fd -lname "socket:\[$inode\]" 2>/dev/null | cut -d/ -f3 | head -1)
            if [ -n "$pid" ]; then
                echo "发现占用进程 PID: $pid (via /proc)，正在终止..."
                kill -9 "$pid" 2>/dev/null || true
                sleep 1
                return 0
            fi
        fi
    fi

    return 1
}

cleanup_port "$PORT" || log "未找到可用的端口检查工具，跳过端口清理（端口可能已被占用）。"

# 二次确认端口状态
log "验证端口 $PORT 是否已释放..."
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
    log "失败：端口 $PORT 仍被占用，无法继续。"
    exit 1
fi
log "端口 $PORT 已释放。"

# 清理同名残留进程
pkill -9 -f "$CMD" 2>/dev/null || true
sleep 1
log "同名进程清理完成。"

rm -f "$WORK_DIR/hxonline.pid"
log "已清理 pid 文件。"

# ========== 5. 启动服务 ==========
start_service() {
    log "正在启动 hxonline..."
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

RETRY=0
while [ $RETRY -lt $MAX_RETRY ]; do
    if start_service; then
        # ========== 6. 获取公网 IP ==========
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
            # 本机网卡公网 IP
            ip=$(timeout 3 ip -4 addr show scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
            if [ -n "$ip" ]; then
                echo "$ip"
                return 0
            fi
            return 1
        }

        SERVER_IP=$(get_public_ip)
        if [ -z "$SERVER_IP" ]; then
            echo "警告：自动获取公网 IP 失败。"
            read -p "请手动输入服务器的公网 IP 地址（留空将使用内网地址）: " SERVER_IP
            if [ -z "$SERVER_IP" ]; then
                SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
                [ -z "$SERVER_IP" ] && SERVER_IP="127.0.0.1"
                echo "已回退使用内网地址。"
            fi
        fi

        echo ""
        echo "=========================================="
        echo "  游戏后端启动成功！"
        echo "=========================================="
        echo "验证地址：http://${SERVER_IP}:${PORT}/hello"
        echo "联机地址：ws://${SERVER_IP}:${PORT}"
        echo "日志文件：$LOG_FILE"
        echo "如果无法访问请去服务器防火墙开放端口"
        exit 0
    fi
    RETRY=$((RETRY+1))
    if [ $RETRY -lt $MAX_RETRY ]; then
        log "将在 ${RETRY_DELAY} 秒后重试（第 $RETRY/$MAX_RETRY 次）..."
        sleep $RETRY_DELAY
    fi
done

log "失败：已重试 $MAX_RETRY 次，hxonline 仍无法启动。"
log "=== 启动失败 ==="
exit 1
