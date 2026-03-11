#!/bin/bash
# uninstall.sh — Удаление прокси-системы
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

PROXY_DIR="$HOME/.proxy"
ZSHRC="$HOME/.zshrc"

echo -e "${RED}Удаление Proxy Manager${NC}"
echo ""

# 1. Убить web-сервер если запущен
pkill -f "proxy-server.py" 2>/dev/null && echo -e "${GREEN}✓${NC} Web-сервер остановлен" || true

# 2. Убрать прокси-переменные из текущей сессии
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy

# 3. Убрать строку из .zshrc
if [ -f "$ZSHRC" ]; then
    # Убрать строку с source и комментарий перед ней
    sed -i '' '/# Proxy Manager/d' "$ZSHRC"
    sed -i '' '/\.proxy\/init\.sh/d' "$ZSHRC"
    echo -e "${GREEN}✓${NC} Убрано из .zshrc"
fi

# 4. Удалить ~/.proxy/ (но сохранить profiles.conf на всякий случай)
if [ -d "$PROXY_DIR" ]; then
    if [ -f "$PROXY_DIR/profiles.conf" ]; then
        cp "$PROXY_DIR/profiles.conf" "/tmp/proxy-profiles-backup.conf"
        echo -e "${YELLOW}→${NC} Бэкап profiles.conf → /tmp/proxy-profiles-backup.conf"
    fi
    rm -rf "$PROXY_DIR"
    echo -e "${GREEN}✓${NC} $PROXY_DIR удалён"
fi

echo ""
echo -e "${GREEN}✓ Удалено.${NC} Перезапусти терминал."
