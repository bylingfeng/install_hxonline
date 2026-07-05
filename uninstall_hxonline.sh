#!/bin/bash
# 卸载 hxonline 游戏后端（支持自定义目录 + 二次确认）

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请以 root 身份运行本脚本。${NC}"
    echo -e "执行： ${YELLOW}sudo su -${NC} 切换后再运行。"
    exit 1
fi

clear
echo -e "${CYAN}"
echo "  ██╗      ███████╗"
echo "  ██║      ██╔════╝"
echo "  ██║      █████╗  "
echo "  ██║      ██╔══╝  "
echo "  ███████╗ ██║     "
echo "  ╚══════╝ ╚═╝     "
echo -e "${NC}"
echo -e "${BOLD}${RED}      幻想纹章Next后端 - 卸载脚本${NC}"
echo ""

# ---- 检测安装目录 ----
if [ -d /mnt/hxonline ]; then
    WORK_DIR="/mnt/hxonline"
    echo -e "${CYAN}检测到默认安装目录：${WORK_DIR}${NC}"
else
    echo -e "${YELLOW}未检测到默认安装目录 /mnt/hxonline${NC}"
    while true; do
        echo -n -e "${CYAN}请输入后端安装目录（如果已删除则输入 none）: ${NC}"
        read WORK_DIR
        if [ -d "$WORK_DIR" ] || [ "$WORK_DIR" = "none" ]; then
            break
        else
            echo -e "${RED}目录不存在，请重新输入或输入 none 跳过。${NC}"
        fi
    done
fi

# ---- 第一步确认：停止服务与终止进程 ----
echo ""
echo -e "${BOLD}${YELLOW}第一步：停止服务并终止进程${NC}"
echo "这将执行："
echo "  1. 停止并禁用 hxonline 系统服务（如果存在）"
echo "  2. 删除定时重启任务（crontab）"
echo "  3. 强制终止所有 hxonline 进程"
echo ""
echo -n -e "${BOLD}确认执行？(y/n): ${NC}"
read STEP1
if [[ "${STEP1,,}" != "y" ]]; then
    echo -e "${GREEN}已取消，未进行任何更改。${NC}"
    exit 0
fi

# 执行 systemd 清理
if command -v systemctl &> /dev/null; then
    if systemctl is-active --quiet hxonline 2>/dev/null; then
        echo -e "${CYAN}正在停止 hxonline 服务...${NC}"
        systemctl stop hxonline 2>/dev/null
    fi
    if systemctl is-enabled --quiet hxonline 2>/dev/null; then
        echo -e "${CYAN}正在禁用开机自启...${NC}"
        systemctl disable hxonline 2>/dev/null
    fi
    if [ -f /etc/systemd/system/hxonline.service ]; then
        echo -e "${CYAN}正在删除服务文件...${NC}"
        rm -f /etc/systemd/system/hxonline.service
        systemctl daemon-reload
    fi
    echo -e "${GREEN}systemd 服务已清理。${NC}"
else
    echo -e "${YELLOW}未检测到 systemd，跳过服务管理。${NC}"
fi

# 删除定时任务
echo -e "${CYAN}正在清理定时重启任务...${NC}"
if crontab -l 2>/dev/null | grep -qi "hxonline"; then
    crontab -l 2>/dev/null | grep -vi "hxonline" | crontab -
    echo -e "${GREEN}已移除所有包含 hxonline 的 cron 任务。${NC}"
else
    echo -e "${YELLOW}未发现定时重启任务。${NC}"
fi

# 终止进程
echo -e "${CYAN}正在终止所有 hxonline 进程...${NC}"
PIDS=$(pgrep -x hxonline 2>/dev/null) || true
if [ -n "$PIDS" ]; then
    echo -e "发现进程 PID: $PIDS"
    kill -9 $PIDS 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}进程已终止。${NC}"
else
    echo -e "${YELLOW}未发现运行中的 hxonline 进程。${NC}"
fi

echo -e "${GREEN}服务与进程清理完毕。${NC}"

# ---- 第二步确认：删除工作目录及日志 ----
echo ""
echo -e "${BOLD}${YELLOW}第二步：删除程序文件与日志${NC}"
if [ "$WORK_DIR" != "none" ] && [ -d "$WORK_DIR" ]; then
    echo -e "将要删除目录：${CYAN}$WORK_DIR${NC}（包含二进制、日志等）"
    echo -e "${RED}注意：此操作不可逆，请确认已备份重要日志。${NC}"
    echo ""
    echo -n -e "${BOLD}确认删除？(y/n): ${NC}"
    read STEP2
    if [[ "${STEP2,,}" == "y" ]]; then
        echo -e "${CYAN}正在删除 $WORK_DIR ...${NC}"
        rm -rf "$WORK_DIR"
        echo -e "${GREEN}工作目录已删除。${NC}"
    else
        echo -e "${YELLOW}已跳过删除目录，如有需要可手动执行：${NC}"
        echo -e "  ${CYAN}rm -rf $WORK_DIR${NC}"
    fi
else
    echo -e "${YELLOW}未找到工作目录，跳过。${NC}"
fi

# ---- 第三步确认：删除安装/卸载脚本 ----
echo ""
echo -e "${BOLD}${YELLOW}第三步：删除当前目录下的安装/卸载脚本${NC}"
echo -e "即将删除：${CYAN}install_hxonline.sh${NC} 和 ${CYAN}uninstall_hxonline.sh${NC}（如果存在）"
echo ""
echo -n -e "${BOLD}确认删除？(y/n): ${NC}"
read STEP3
if [[ "${STEP3,,}" == "y" ]]; then
    [ -f install_hxonline.sh ] && rm -f install_hxonline.sh && echo -e "${CYAN}已删除 install_hxonline.sh${NC}"
    [ -f uninstall_hxonline.sh ] && rm -f uninstall_hxonline.sh && echo -e "${CYAN}已删除 uninstall_hxonline.sh${NC}"
else
    echo -e "${YELLOW}已跳过删除脚本。${NC}"
fi

echo ""
echo -e "${YELLOW}如果之前手动添加了防火墙规则，请自行移除。${NC}"
echo ""
echo -e "${BOLD}${GREEN}=========================================="
echo "  卸载完成！hxonline 已从系统中彻底移除。"
echo -e "==========================================${NC}"