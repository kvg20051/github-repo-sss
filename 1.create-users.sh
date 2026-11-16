#!/usr/bin/env bash
# Пользователи kvg (sudo), kvg1, toor (UID 0) + запрет SSH для root/toor — Ubuntu 26
set -euo pipefail

FULLNAME="Victor G. Krivulets"
SSHD_DROPIN="/etc/ssh/sshd_config.d/00-deny-root.conf"

if [[ $EUID -ne 0 ]]; then
    echo "Запустите от root: sudo $0" >&2
    exit 1
fi

# --- 1. kvg: пользователь с правами sudo -----------------------------------
if id kvg &>/dev/null; then
    echo "kvg уже существует — пропускаю создание"
else
    useradd -m -s /bin/bash -c "$FULLNAME" -G sudo kvg
    echo "Создан kvg"
fi
usermod -aG sudo kvg
echo "Пароль для kvg:"
passwd kvg

# --- 2. kvg1: обычный пользователь (без sudo) ------------------------------
if id kvg1 &>/dev/null; then
    echo "kvg1 уже существует — пропускаю создание"
else
    useradd -m -s /bin/bash -c "$FULLNAME" kvg1
    echo "Создан kvg1"
fi
echo "Пароль для kvg1:"
passwd kvg1

# --- 3. toor: второй суперпользователь (UID 0, GID 0) ----------------------
if id toor &>/dev/null; then
    echo "toor уже существует — пропускаю создание"
else
    # -o разрешает неуникальный UID; домашний каталог общий с root
    useradd -o -u 0 -g 0 -M -d /root -s /bin/bash -c "$FULLNAME" toor
    echo "Создан toor (UID 0)"
fi
echo "Пароль для toor:"
passwd toor

# --- 4. SSH: запрет входа для root и toor ----------------------------------
# В sshd действует первое найденное значение, а файлы из sshd_config.d
# подключаются в начале sshd_config, поэтому префикс 00- гарантирует приоритет.
cat > "$SSHD_DROPIN" <<'EOF'
# Создано create-users.sh: вход по SSH для root и toor запрещён
PermitRootLogin no
DenyUsers root toor
EOF
chmod 644 "$SSHD_DROPIN"

if sshd -t; then
    systemctl try-reload-or-restart ssh
    echo "Конфиг SSH применён ($SSHD_DROPIN)"
else
    echo "ОШИБКА в конфиге SSH — изменения не применены, проверьте $SSHD_DROPIN" >&2
    exit 1
fi

# --- Проверка ---------------------------------------------------------------
echo
echo "Итог:"
getent passwd kvg kvg1 toor
id kvg; id kvg1; id toor
echo
echo "Учётные записи с UID 0:"
awk -F: '$3 == 0 {print "  " $1}' /etc/passwd
echo
echo "Действующие настройки SSH:"
sshd -T | grep -Ei '^(permitrootlogin|denyusers)'
