#!/usr/bin/env bash
set -Eeuo pipefail

export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

# Можно переопределить при запуске: sudo SSH_PORT=2222 bash ...
SSH_PORT="${SSH_PORT:-22}"

if (( EUID != 0 )); then
    echo "Запустите скрипт через sudo или от root." >&2
    exit 1
fi

source /etc/os-release
case "$ID" in
    ubuntu|debian) ;;
    *)
        echo "Скрипт предназначен для Ubuntu/Debian." >&2
        exit 1
        ;;
esac

if [[ ! -d /run/systemd/system ]]; then
    echo "Для работы скрипта требуется systemd." >&2
    exit 1
fi

if [[ ! "$SSH_PORT" =~ ^[0-9]{1,5}$ ]]; then
    echo "SSH_PORT должен быть числом от 1 до 65535." >&2
    exit 1
fi

SSH_PORT=$((10#$SSH_PORT))
if (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
    echo "Недопустимый SSH_PORT." >&2
    exit 1
fi

trusted_sources=(
    46.8.181.72
    46.8.181.70
    46.8.181.71
    46.8.181.42
    46.8.180.83
    132.243.22.149
    46.166.168.18
    85.30.248.159
    185.9.77.170
    95.31.179.122
    79.98.30.0/24
    188.92.178.0/24
    194.186.246.0/24
    195.239.14.0/24
    10.125.125.0/24
    10.124.124.0/24
    10.123.123.0/24
    10.66.66.0/24
    10.5.5.0/24
)

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    fail2ban python3-systemd iptables

config="/etc/fail2ban/jail.d/99-sshd-trusted.local"
backup=""
ignore_ips="127.0.0.1/8 ::1 ${trusted_sources[*]}"

install -d -m 0755 /etc/fail2ban/jail.d

if [[ -e "$config" ]]; then
    backup="$(mktemp "${config}.bak.XXXXXX")"
    cp -a -- "$config" "$backup"
    echo "Резервная копия: $backup"
fi

cat > "$config" <<EOF
[DEFAULT]
ignoreip = $ignore_ips

[sshd]
enabled = true
filter = sshd
backend = systemd
port = $SSH_PORT
protocol = tcp

banaction = iptables-multiport
bantime = 1h
findtime = 10m
maxretry = 5

ignoreip = $ignore_ips
EOF

chmod 0644 "$config"

# При ошибке проверки восстанавливаем предыдущий файл.
if ! fail2ban-client -t; then
    if [[ -n "$backup" ]]; then
        cp -a -- "$backup" "$config"
    else
        rm -f -- "$config"
    fi
    echo "Ошибка конфигурации. Изменение файла отменено." >&2
    exit 1
fi

systemctl enable fail2ban
systemctl restart fail2ban

# Ждём готовности SSH jail.
ready=0
for ((attempt = 0; attempt < 20; attempt++)); do
    if fail2ban-client status sshd >/dev/null 2>&1; then
        ready=1
        break
    fi
    sleep 1
done

if (( ready == 0 )); then
    journalctl -u fail2ban -n 50 --no-pager
    exit 1
fi

echo "Fail2ban настроен. Защищаемый SSH-порт: $SSH_PORT"
fail2ban-client status sshd
fail2ban-client get sshd ignoreip
