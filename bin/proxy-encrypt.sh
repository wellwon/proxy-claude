#!/bin/bash
# proxy-encrypt.sh — Шифрует profiles.conf для безопасного хранения в git
# Использование: proxy-encrypt.sh [--decrypt]

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PROXY_DIR="${PROXY_DIR:-$HOME/.proxy}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

CONF="$PROXY_DIR/profiles.conf"
ENC="$PROJECT_DIR/profiles.conf.enc"

if [ "$1" = "--decrypt" ]; then
    # Расшифровка
    if [ ! -f "$ENC" ]; then
        echo -e "${RED}✗${NC} Файл $ENC не найден"
        exit 1
    fi
    echo -e "${CYAN}Расшифровка профилей...${NC}"
    read -s -p "Пароль команды: " TEAM_PASS
    echo ""
    if openssl enc -aes-256-cbc -d -pbkdf2 -in "$ENC" -out "$CONF" -pass "pass:$TEAM_PASS" 2>/dev/null; then
        count=$(grep -v '^#' "$CONF" | grep -v '^\s*$' | wc -l | tr -d ' ')
        echo -e "${GREEN}✓${NC} Расшифровано: ${BOLD}$count${NC} профилей → $CONF"
    else
        rm -f "$CONF"
        echo -e "${RED}✗${NC} Неверный пароль или повреждённый файл"
        exit 1
    fi
else
    # Шифрование
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}✗${NC} Файл $CONF не найден"
        echo -e "Сначала добавь профили в $CONF"
        exit 1
    fi
    count=$(grep -v '^#' "$CONF" | grep -v '^\s*$' | wc -l | tr -d ' ')
    echo -e "${CYAN}Шифрование ${BOLD}$count${NC}${CYAN} профилей...${NC}"
    read -s -p "Придумай пароль команды: " TEAM_PASS
    echo ""
    read -s -p "Подтверди пароль: " TEAM_PASS2
    echo ""
    if [ "$TEAM_PASS" != "$TEAM_PASS2" ]; then
        echo -e "${RED}✗${NC} Пароли не совпадают"
        exit 1
    fi
    if [ -z "$TEAM_PASS" ]; then
        echo -e "${RED}✗${NC} Пароль не может быть пустым"
        exit 1
    fi
    openssl enc -aes-256-cbc -pbkdf2 -in "$CONF" -out "$ENC" -pass "pass:$TEAM_PASS"
    echo -e "${GREEN}✓${NC} Зашифровано → ${BOLD}$ENC${NC}"
    echo -e "Теперь можно закоммитить ${BOLD}profiles.conf.enc${NC} в git"
fi
