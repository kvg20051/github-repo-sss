#!/usr/bin/env bash
# Создание пользователей kvg (sudo) и toor (UID 0) — Ubuntu 26
set -euo pipefail

FULLNAME="Victor G. Krivulets"

if [[ $EUID -ne 0 ]]; then
    echo "Запустите от root: sudo $0" >&2
    exit 1
fi

# --- 1. kvg: обычный пользователь с правами sudo ---------------------------
if id kvg &>/dev/null; then
    echo "kvg уже существует — пропускаю создание"
else
    useradd -m -s /bin/bash -c "$FULLNAME" -G sudo kvg
    echo "Создан kvg"
fi
usermod -aG sudo kvg
echo "Пароль для kvg:"
passwd kvg

# --- 2. toor: второй суперпользователь (UID 0, GID 0) ----------------------
if id toor &>/dev/null; then
    echo "toor уже существует — пропускаю создание"
else
    # -o разрешает неуникальный UID; домашний каталог общий с root
    useradd -o -u 0 -g 0 -M -d /root -s /bin/bash -c "$FULLNAME" toor
    echo "Создан toor (UID 0)"
fi
echo "Пароль для toor:"
passwd toor

# --- Проверка ---------------------------------------------------------------
echo
echo "Итог:"
getent passwd kvg toor
id kvg
id toor
echo
echo "Учётные записи с UID 0:"
awk -F: '$3 == 0 {print "  " $1}' /etc/passwd
