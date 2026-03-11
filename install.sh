#!/bin/bash
# install.sh — Установка прокси-системы на Mac
# Запуск: ./install.sh или curl ... | bash
#
# Что делает:
# 1. Копирует файлы в ~/.proxy/
# 2. Создаёт profiles.conf (если нет)
# 3. Добавляет source в ~/.zshrc
# 4. Готово

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

PROXY_DIR="$HOME/.proxy"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ZSHRC="$HOME/.zshrc"
INIT_LINE='source "$HOME/.proxy/init.sh"'

echo -e "${CYAN}══════════════════════════════════${NC}"
echo -e "${BOLD}  Proxy Manager — Установка${NC}"
echo -e "${CYAN}══════════════════════════════════${NC}"
echo ""

# 1. Создать ~/.proxy/ и скопировать файлы
echo -e "${CYAN}[1/4]${NC} Копирую файлы в $PROXY_DIR..."
mkdir -p "$PROXY_DIR/bin" "$PROXY_DIR/web"

cp "$SCRIPT_DIR/bin/proxy-check.sh"   "$PROXY_DIR/bin/"
cp "$SCRIPT_DIR/bin/proxy-switch.sh"  "$PROXY_DIR/bin/"
cp "$SCRIPT_DIR/bin/proxy-server.py"  "$PROXY_DIR/bin/"
cp "$SCRIPT_DIR/bin/proxy-encrypt.sh" "$PROXY_DIR/bin/"
cp "$SCRIPT_DIR/init.sh"             "$PROXY_DIR/"
cp "$SCRIPT_DIR/web/index.html"      "$PROXY_DIR/web/"

chmod +x "$PROXY_DIR/bin/proxy-check.sh"
chmod +x "$PROXY_DIR/bin/proxy-switch.sh"
chmod +x "$PROXY_DIR/bin/proxy-server.py"
chmod +x "$PROXY_DIR/bin/proxy-encrypt.sh"

echo -e "  ${GREEN}✓${NC} Файлы скопированы"

# 2. Настроить профили
echo -e "${CYAN}[2/4]${NC} Настраиваю профили..."
if [ -f "$PROXY_DIR/profiles.conf" ]; then
    echo -e "  ${YELLOW}→${NC} profiles.conf уже существует, пропускаю"
elif [ -f "$SCRIPT_DIR/profiles.conf" ]; then
    # Локальный незашифрованный файл (у владельца)
    cp "$SCRIPT_DIR/profiles.conf" "$PROXY_DIR/"
    echo -e "  ${GREEN}✓${NC} profiles.conf скопирован"
elif [ -f "$SCRIPT_DIR/profiles.conf.enc" ]; then
    # Зашифрованный файл из git — расшифровываем
    echo -e "  ${CYAN}Найден зашифрованный файл профилей${NC}"
    read -s -p "  Введи пароль команды: " TEAM_PASS
    echo ""
    if openssl enc -aes-256-cbc -d -pbkdf2 \
        -in "$SCRIPT_DIR/profiles.conf.enc" \
        -out "$PROXY_DIR/profiles.conf" \
        -pass "pass:$TEAM_PASS" 2>/dev/null; then
        count=$(grep -v '^#' "$PROXY_DIR/profiles.conf" | grep -v '^\s*$' | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✓${NC} Расшифровано: ${BOLD}$count${NC} профилей"
    else
        rm -f "$PROXY_DIR/profiles.conf"
        echo -e "  ${RED}✗${NC} Неверный пароль! Профили не расшифрованы"
        echo -e "  ${DIM}Попробуй снова: ./install.sh${NC}"
        echo -e "  ${DIM}Или добавь вручную: nano $PROXY_DIR/profiles.conf${NC}"
        cp "$SCRIPT_DIR/profiles.conf.example" "$PROXY_DIR/profiles.conf"
    fi
else
    cp "$SCRIPT_DIR/profiles.conf.example" "$PROXY_DIR/profiles.conf"
    echo -e "  ${YELLOW}→${NC} Создан profiles.conf из примера"
    echo -e "  ${DIM}Отредактируй: nano $PROXY_DIR/profiles.conf${NC}"
fi

# 3. Добавить в ~/.zshrc
echo -e "${CYAN}[3/4]${NC} Настраиваю ~/.zshrc..."
if grep -qF '.proxy/init.sh' "$ZSHRC" 2>/dev/null; then
    echo -e "  ${YELLOW}→${NC} Уже подключено в .zshrc"
else
    # Добавить перед первым alias или в конец
    echo "" >> "$ZSHRC"
    echo "# Proxy Manager" >> "$ZSHRC"
    echo "$INIT_LINE" >> "$ZSHRC"
    echo -e "  ${GREEN}✓${NC} Добавлено в .zshrc"
fi

# 5. Записать активный профиль
echo -e "${CYAN}[4/4]${NC} Активирую..."
if [ -f "$PROXY_DIR/profiles.conf" ]; then
    # Взять первый профиль как дефолтный
    first=$(grep -v '^#' "$PROXY_DIR/profiles.conf" | grep -v '^\s*$' | head -1 | cut -d'|' -f1)
    if [ -n "$first" ]; then
        echo "$first" > "$PROXY_DIR/active"
        echo -e "  ${GREEN}✓${NC} Активный профиль: ${BOLD}$first${NC}"
    fi
fi

echo ""
echo -e "${GREEN}══════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ Установка завершена!${NC}"
echo -e "${GREEN}══════════════════════════════════${NC}"
echo ""
echo -e "Команды:"
echo -e "  ${BOLD}px${NC}              — статус прокси (IP, страна, ISP)"
echo -e "  ${BOLD}pxf${NC}             — полный отчёт"
echo -e "  ${BOLD}pxl${NC}             — список профилей"
echo -e "  ${BOLD}pxto <name>${NC}     — переключить профиль"
echo -e "  ${BOLD}pxoff${NC}           — выключить прокси"
echo -e "  ${BOLD}pxon${NC}            — включить обратно"
echo -e "  ${BOLD}pxweb${NC}           — запустить web-панель (localhost:7777)"
echo ""
echo -e "${DIM}Перезапусти терминал или выполни: source ~/.zshrc${NC}"
