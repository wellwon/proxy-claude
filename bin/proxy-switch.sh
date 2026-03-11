#!/bin/bash
# proxy-switch.sh — Переключение между прокси-профилями
# Использование (через source!):
#   source proxy-switch.sh <profile-name>    — переключить
#   source proxy-switch.sh --off             — выключить
#   proxy-switch.sh --list                   — список
#   proxy-switch.sh --add <name> <proto> <user:pass@host:port>

PROXY_DIR="${PROXY_DIR:-$HOME/.proxy}"
CONF="$PROXY_DIR/profiles.conf"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

list_profiles() {
    if [ ! -f "$CONF" ]; then
        echo -e "${RED}✗ Нет profiles.conf — запусти install.sh${NC}"
        return 1
    fi
    echo -e "${CYAN}Доступные профили:${NC}"
    while IFS='|' read -r name proto addr; do
        [ -z "$name" ] || [[ "$name" == \#* ]] && continue
        host=$(echo "$addr" | sed 's/.*@//')
        echo -e "  ${BOLD}$name${NC} ${DIM}($proto → $host)${NC}"
    done < "$CONF"
}

add_profile() {
    local name="$1" proto="$2" addr="$3"
    if [ -z "$name" ] || [ -z "$proto" ] || [ -z "$addr" ]; then
        echo -e "${RED}Формат: proxy-switch.sh --add <name> <http|socks5> <user:pass@host:port>${NC}"
        return 1
    fi
    echo "$name|$proto|$addr" >> "$CONF"
    echo -e "${GREEN}✓${NC} Профиль ${BOLD}$name${NC} добавлен"
}

case "$1" in
    --list|-l)
        list_profiles
        return 0 2>/dev/null || exit 0
        ;;
    --off)
        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY
        echo "" > "$PROXY_DIR/active"
        echo -e "${YELLOW}⚡ Proxy OFF${NC} — прямое соединение"
        return 0 2>/dev/null || exit 0
        ;;
    --add|-a)
        add_profile "$2" "$3" "$4"
        return 0 2>/dev/null || exit 0
        ;;
    --help|-h|"")
        echo "proxy-switch.sh — управление прокси-профилями"
        echo ""
        echo "Использование:"
        echo "  source proxy-switch.sh <name>              Переключить на профиль"
        echo "  source proxy-switch.sh --off               Выключить прокси"
        echo "  proxy-switch.sh --list                     Список профилей"
        echo "  proxy-switch.sh --add <n> <proto> <addr>   Добавить профиль"
        return 0 2>/dev/null || exit 0
        ;;
esac

# Переключить на профиль
profile_name="$1"
found=false

if [ ! -f "$CONF" ]; then
    echo -e "${RED}✗ Нет profiles.conf${NC}"
    return 1 2>/dev/null || exit 1
fi

while IFS='|' read -r name proto addr; do
    [ -z "$name" ] || [[ "$name" == \#* ]] && continue
    if [ "$name" = "$profile_name" ]; then
        found=true

        if [ "$proto" = "socks5" ]; then
            export all_proxy="socks5://$addr"
            export ALL_PROXY="$all_proxy"
            export http_proxy="socks5h://$addr"
            export https_proxy="socks5h://$addr"
        else
            export http_proxy="http://$addr"
            export https_proxy="http://$addr"
            unset all_proxy ALL_PROXY
        fi

        export HTTP_PROXY="$http_proxy"
        export HTTPS_PROXY="$https_proxy"
        export no_proxy="localhost,127.0.0.1,.local,192.168.0.0/16,10.0.0.0/8"

        # Записать активный профиль
        echo "$profile_name" > "$PROXY_DIR/active"

        # Показать статус
        proxy-check.sh
        break
    fi
done < "$CONF"

if [ "$found" = false ]; then
    echo -e "${RED}✗ Профиль '$profile_name' не найден${NC}"
    echo ""
    list_profiles
    return 1 2>/dev/null || exit 1
fi
