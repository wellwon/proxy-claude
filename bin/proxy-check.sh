#!/bin/bash
# proxy-check.sh — Проверка статуса прокси с геолокацией
# Использование: proxy-check.sh [--full]

PROXY_DIR="${PROXY_DIR:-$HOME/.proxy}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'
BOLD='\033[1m'

full=false
[ "$1" = "--full" ] && full=true

# Получить IP + гео одним запросом
geo=$(curl -s --max-time 5 'http://ip-api.com/json/?fields=status,country,countryCode,regionName,city,isp,org,query' 2>/dev/null)

if [ -z "$geo" ] || echo "$geo" | grep -q '"status":"fail"'; then
    echo -e "${RED}✗ Нет интернета или прокси недоступен${NC}"
    exit 1
fi

ip=$(echo "$geo" | sed -n 's/.*"query":"\([^"]*\)".*/\1/p')
country=$(echo "$geo" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
cc=$(echo "$geo" | sed -n 's/.*"countryCode":"\([^"]*\)".*/\1/p')
city=$(echo "$geo" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
region=$(echo "$geo" | sed -n 's/.*"regionName":"\([^"]*\)".*/\1/p')
isp=$(echo "$geo" | sed -n 's/.*"isp":"\([^"]*\)".*/\1/p')
org=$(echo "$geo" | sed -n 's/.*"org":"\([^"]*\)".*/\1/p')

# Флаг страны (emoji) — через python для кроссплатформенности
flag=""
if [ -n "$cc" ]; then
    flag=$(python3 -c "print(''.join(chr(0x1F1E6 + ord(c) - ord('A')) for c in '$cc'))" 2>/dev/null)
fi

# Проверка: есть ли прокси-переменные?
has_proxy=false
[ -n "$http_proxy" ] || [ -n "$HTTP_PROXY" ] && has_proxy=true

# Определить имя активного профиля
profile_name=""
conf="$PROXY_DIR/profiles.conf"
if [ -f "$conf" ]; then
    while IFS='|' read -r name proto addr; do
        [ -z "$name" ] || [[ "$name" == \#* ]] && continue
        proxy_host=$(echo "$addr" | sed 's/.*@//' | cut -d: -f1)
        if echo "$http_proxy$HTTP_PROXY" | grep -q "$proxy_host"; then
            profile_name="$name"
            break
        fi
    done < "$conf"
fi

if [ "$has_proxy" = true ]; then
    label=""
    [ -n "$profile_name" ] && label=" ${DIM}[$profile_name]${NC}"
    echo -e "${GREEN}🛡 PROXY${NC} $flag ${BOLD}$ip${NC} — $city, $region, $country ${DIM}($isp)${NC}$label"
else
    echo -e "${YELLOW}⚡ DIRECT${NC} $flag ${BOLD}$ip${NC} — $city, $region, $country ${DIM}($isp)${NC}"
fi

# Полный отчёт
if [ "$full" = true ]; then
    echo ""
    echo -e "${CYAN}── Детали IP ──${NC}"
    echo -e "  IP:       $ip"
    echo -e "  Страна:   $flag $country ($cc)"
    echo -e "  Город:    $city, $region"
    echo -e "  ISP:      $isp"
    echo -e "  Org:      $org"

    echo ""
    echo -e "${CYAN}── Переменные окружения ──${NC}"
    for var in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy no_proxy; do
        val="${!var}"
        if [ -n "$val" ]; then
            masked=$(echo "$val" | sed 's|://[^:]*:[^@]*@|://***:***@|')
            echo -e "  ${GREEN}✓${NC} $var = $masked"
        else
            echo -e "  ${DIM}–${NC} $var"
        fi
    done

    echo ""
    echo -e "${CYAN}── Тест сервисов ──${NC}"
    for svc in "GitHub API|https://api.github.com" "PyPI|https://pypi.org/simple/" "Anthropic|https://api.anthropic.com" "OpenRouter|https://openrouter.ai/api/v1"; do
        name="${svc%%|*}"
        url="${svc##*|}"
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
        if [ "$code" = "000" ]; then
            echo -e "  ${RED}✗${NC} $name — timeout"
        else
            echo -e "  ${GREEN}✓${NC} $name — $code"
        fi
    done

    echo ""
    echo -e "${CYAN}── Профили ──${NC}"
    if [ -f "$conf" ]; then
        while IFS='|' read -r name proto addr; do
            [ -z "$name" ] || [[ "$name" == \#* ]] && continue
            proxy_host=$(echo "$addr" | sed 's/.*@//' | cut -d: -f1)
            if echo "$http_proxy$HTTP_PROXY" | grep -q "$proxy_host"; then
                echo -e "  ${GREEN}●${NC} $name ($proto) — ${GREEN}активен${NC}"
            else
                echo -e "  ${DIM}○${NC} $name ($proto)"
            fi
        done < "$conf"
    fi
fi
