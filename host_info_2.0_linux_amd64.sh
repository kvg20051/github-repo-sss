#!/bin/bash

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Convert KB to human readable format
convert_size() {
    local size=$1
    awk -v size="$size" '
    BEGIN {
        units[0]="KB"; units[1]="MB"; units[2]="GB"; units[3]="TB";
        unit_idx = 0;
        
        while (size >= 1024 && unit_idx < 3) {
            size = size / 1024;
            unit_idx++;
        }
        
        printf "%.2f %s", size, units[unit_idx];
    }'
}

show_help() {
    echo -e "${CYAN}Использование: script.sh [опции]${NC}"
    echo -e "${YELLOW}Опции:${NC}"
    echo -e "  ${GREEN}--host              ${NC}Показать информацию о хосте"
    echo -e "  ${GREEN}--users             ${NC}Показать информацию о пользователях"
    echo -e "  ${GREEN}-h, --help          ${NC}Показать help"
}

# Парсинг аргументов командной строки
OPTIONS=$(getopt -o "h" -l "help,host,users,test:" -- "$@")

# Вывод help, если не переданы аргументы
if [[ $# -eq 0 ]]; then
    show_help
    exit 0
fi

# Парсинг и обработка аргументов
eval set -- "$OPTIONS"

while true; do
    case "$1" in
        -h|--help)
            echo "Показать help"
            show_help
            exit 0
            ;;
            
        --host)
            # Проверка на супер пользователя
            if [[ $EUID -ne 0 ]]; then
                echo -e "${RED}Этот скрипт должен быть запущен с правами суперпользователя.${NC}"
                exit 1
            fi

            # Вывод информации о хосте
            echo -e "${BLUE}-----------------------------------------------------------------------------------------------${NC}"
            echo ""
            echo -e "${YELLOW}Информация о хосте:${NC}"
            echo ""
            echo -e "${BLUE}-----------------------------------------------------------------------------------------------${NC}"
            echo -e "${GREEN}Количество ядер в системе:${NC}                         $(nproc)"
            
            # Convert memory values to human readable format
            total_mem=$(free --kilo | awk '/^Mem:/ {print $2}')
            used_mem=$(free --kilo | awk '/^Mem:/ {print $3}')
            total_mem_human=$(convert_size $total_mem)
            used_mem_human=$(convert_size $used_mem)
            
            echo -e "${GREEN}Объём оперативной памяти в системе всего:${NC}          $total_mem_human"
            echo -e "${GREEN}Объём использованной оперативной памяти:${NC}           $used_mem_human"
            echo ""
            echo -e "${YELLOW}Информация о дисках:${NC}"
            
            # Get disk information excluding certain filesystems
            df_output=$(df -h --exclude-type=tmpfs --exclude-type=devtmpfs --exclude-type=overlay)
            
            # Print header
            printf "${CYAN}%-20s %10s %10s %10s %8s  %-25s${NC}\n" \
                "Устройство" "Размер" "Использовано" "Доступно" "Использ%" "Точка монтирования"
            printf "${BLUE}%-20s %10s %10s %10s %8s  %-25s${NC}\n" \
                "----------" "------" "-----------" "---------" "--------" "-----------------"
            
            # Process and print each line of disk information
            echo "$df_output" | awk 'NR>1 {
                # Remove /dev/ prefix from device names for cleaner display
                dev=$1
                sub("/dev/", "", dev)
                # Print formatted output
                printf "%-20s %10s %10s %10s %8s  %-25s\n", 
                    dev, $2, $3, $4, $5, $6
            }'

            echo ""

            # Средняя загрузка и время работы системы
            load_averages=$(awk '{ print $1, $2, $3 }' /proc/loadavg)
            echo -e "${GREEN}Средняя загрузка (load average):${NC}                  ${load_averages}"
            echo -e "${GREEN}Время работы системы:${NC}                             $(uptime -p | awk '{print $2 $3 $4 $5 $6 $7 $8 $9}')"
            echo -e "${GREEN}Текущее время в системе:${NC}                          $(date +"%T")"
            echo ""

            # Сетевые интерфейсы IPv4
            echo -e "${YELLOW}Сетевые интерфейсы IPv4:${NC}"
            # Headers for network interfaces
            printf "${CYAN}%-12s %-35s %12s %12s %12s %12s${NC}\n" "Interface" "IP Address" "RX" "TX" "RX Errors" "TX Errors"
            printf "${BLUE}%-12s %-35s %12s %12s %12s %12s${NC}\n" "----------" "----------" "--" "--" "---------" "---------"
            
            # Получаем список интерфейсов с их IP-адресами
            ip_addresses=$(ip -o -4 addr show | awk '{print $2, $4}')
            # Получаем статистику RX/TX включая ошибки из /proc/net/dev
            rx_tx_stats=$(awk 'NR>2 {print $1, $2, $10, $3, $11}' /proc/net/dev | sed 's/:/ /g')
            # Цикл для вывода информации о сетевых интерфейсах и их статистике
            while read -r iface ip; do
                stats=$(echo "$rx_tx_stats" | grep "^$iface")
                rx=$(echo $stats | awk '{print $2}')
                tx=$(echo $stats | awk '{print $3}')
                rx_errors=$(echo $stats | awk '{print $4}')
                tx_errors=$(echo $stats | awk '{print $5}')
                # Convert RX/TX values to human readable format
                rx_human=$(convert_size $rx)
                tx_human=$(convert_size $tx)
                printf "%-12s %-35s %12s %12s %12s %12s\n" "$iface" "$ip" "$rx_human" "$tx_human" "$rx_errors" "$tx_errors"
            done <<< "$ip_addresses"

            echo ""
            echo -e "${YELLOW}Сетевые интерфейсы IPv6:${NC}"
            printf "${CYAN}%-12s %-35s %12s %12s %12s %12s${NC}\n" "Interface" "IP Address" "RX" "TX" "RX Errors" "TX Errors"
            printf "${BLUE}%-12s %-35s %12s %12s %12s %12s${NC}\n" "----------" "----------" "--" "--" "---------" "---------"

            # Получаем список интерфейсов с их IP-адресами 
            ip_addresses=$(ip -o -6 addr show | awk '{print $2, $4}')
            # Get RX/TX statistics including errors from /proc/net/dev
            rx_tx_stats=$(awk 'NR>2 {print $1, $2, $10, $3, $11}' /proc/net/dev | sed 's/:/ /g')
            # Цикл для вывода информации о сетевых интерфейсах и их статистике
            while read -r iface ip; do
                stats=$(echo "$rx_tx_stats" | grep "^$iface")
                rx=$(echo $stats | awk '{print $2}')
                tx=$(echo $stats | awk '{print $3}')
                rx_errors=$(echo $stats | awk '{print $4}')
                tx_errors=$(echo $stats | awk '{print $5}')
                # Convert RX/TX values to human readable format
                rx_human=$(convert_size $rx)
                tx_human=$(convert_size $tx)
                printf "%-12s %-35s %12s %12s %12s %12s\n" "$iface" "$ip" "$rx_human" "$tx_human" "$rx_errors" "$tx_errors"
            done <<< "$ip_addresses"

            echo -e "${BLUE}-----------------------------------------------------------------------------------------------${NC}"
            # Занятые порты
            echo -e "${YELLOW}Занятые порты:${NC}"
            # Format the port information in a table
            printf "${CYAN}%-15s %-6s %-10s %-6s %-20s %s${NC}\n" "Process" "PID" "User" "FD" "Protocol" "Port (Address)"
            printf "${BLUE}%-15s %-6s %-10s %-6s %-20s %s${NC}\n" "-------" "---" "----" "--" "--------" "-------------"
            port_info=$(lsof -i -P -n | grep LISTEN)
            echo "$port_info" | while read -r process pid user fd protocol addr_info; do
                # Extract port number from address info
                port=$(echo "$addr_info" | grep -o ':[0-9]\+' | cut -d':' -f2)
                addr=$(echo "$addr_info" | sed 's/(LISTEN)//')
                
                # Clean up process name
                process_name=$(echo "$process" | sed 's/\\x20/ /g')
                
                # Format the address:port information
                if [[ $addr == *"::"* ]]; then
                    addr_display="[${addr%:*}]:$port"
                elif [[ $addr == "*"* ]]; then
                    addr_display="*:$port"
                else
                    addr_display="${addr%:*}:$port"
                fi
                
                printf "%-15s %-6s %-10s %-6s %-20s %s\n" \
                    "$process_name" "$pid" "$user" "$fd" "$protocol" "$addr_display"
            done | sort -n -k6 # Sort by port number

            exit 0
            ;;

        --users)
            echo -e "${YELLOW}Показать информацию о пользователях${NC}"
            
            echo -e "${BLUE}-----------------------------------------------------------------------------------------------${NC}"
            echo -e "${YELLOW}Информация о пользователях${NC}"
            echo -e "${BLUE}-----------------------------------------------------------------------------------------------${NC}"
            echo -e "${GREEN}1) список root-пользователей в системе:${NC}"
            getent passwd | awk -F: '$3 == 0 { print $1 }'
            echo -e "${BLUE}-----------------------------------------------------------------------------------------------${NC}"
            echo -e "${GREEN}2) список всех пользователей:${NC}"
            cat /etc/passwd | cut -d: -f1
            echo -e "${BLUE}-----------------------------------------------------------------------------------------------${NC}"
            echo -e "${GREEN}3) список залогиненных пользователей:${NC}"
            who
            exit 0 ;;

        *)
            echo -e "${RED}Неизвестная опция: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done
