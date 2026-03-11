#!/bin/bash
# init.sh — Инициализация прокси. Подключается через source в ~/.zshrc
# Читает активный профиль из ~/.proxy/active + ~/.proxy/profiles.conf

export PROXY_DIR="$HOME/.proxy"
export PATH="$PROXY_DIR/bin:$PATH"

# Загрузить активный профиль из конфига
_proxy_load() {
    local active_name conf_file
    active_name=$(cat "$PROXY_DIR/active" 2>/dev/null)
    conf_file="$PROXY_DIR/profiles.conf"

    # Сбросить предыдущие
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY

    [ -z "$active_name" ] && return
    [ ! -f "$conf_file" ] && return

    while IFS='|' read -r name proto addr; do
        [ -z "$name" ] || [[ "$name" == \#* ]] && continue
        if [ "$name" = "$active_name" ]; then
            if [ "$proto" = "socks5" ]; then
                export all_proxy="socks5://$addr"
                export ALL_PROXY="$all_proxy"
                export http_proxy="socks5h://$addr"
                export https_proxy="socks5h://$addr"
            else
                export http_proxy="http://$addr"
                export https_proxy="http://$addr"
            fi
            export HTTP_PROXY="$http_proxy"
            export HTTPS_PROXY="$https_proxy"
            export no_proxy="localhost,127.0.0.1,.local,192.168.0.0/16,10.0.0.0/8"
            return
        fi
    done < "$conf_file"
}

_proxy_load

# Алиасы
alias px="proxy-check.sh"                          # быстрый статус
alias pxf="proxy-check.sh --full"                  # полный отчёт
alias pxl="proxy-switch.sh --list"                  # список профилей
alias pxoff="source proxy-switch.sh --off"          # выключить
alias pxon="_proxy_load && proxy-check.sh"          # перечитать из конфига
alias pxweb="PROXY_DIR=\"\$PROXY_DIR\" python3 \$PROXY_DIR/bin/proxy-server.py &"
pxto() { source proxy-switch.sh "$1"; }             # переключить: pxto de-berlin
pxsync() { _proxy_load && proxy-check.sh; }         # синхронизировать с web-панелью

# Автопроверка при старте терминала
proxy-check.sh 2>/dev/null
