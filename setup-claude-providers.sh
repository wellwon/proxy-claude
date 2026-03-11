#!/bin/bash
# ============================================================
# Настройка Claude Code с тремя провайдерами: opus / kimi / max
# Запуск: bash setup-claude-providers.sh
# ============================================================

set -e

# ---- КЛЮЧИ (замени на свои!) ----
MINIMAX_API_KEY="sk-cp-FU2WDTbMIi_meR0NlrHbsfGwtaYjhIGIDYmEcjlXWQHFda5yFcKCQ1JXCyWQzAV9EH_PMT7sZcu6uSNUN2Umgf9TSkm6pzvbw4RGWq_AmWpyuSOzEBrw2xY"
KIMI_API_KEY="sk-kimi-e6wgf5c1oWizBgH13Ht9SA1RB3Q1gPrKv1IdTR2ipBa77dU9D2tuPt11nfS17WrF"
# Anthropic авторизуется через `claude` нативно (oauth), ключ не нужен
# ----------------------------------

echo "=== 1. Установка Claude Code (если нет) ==="
if ! command -v claude &>/dev/null; then
    npm install -g @anthropic-ai/claude-code
    echo "→ Claude Code установлен"
else
    echo "→ Claude Code уже есть: $(claude --version)"
fi

echo ""
echo "=== 2. Установка cc-mirror ==="
npm install -g cc-mirror
echo "→ cc-mirror установлен"

echo ""
echo "=== 3. Создание провайдеров ==="

# MiniMax M2.5
echo "--- MiniMax ---"
cc-mirror quick --provider minimax --api-key "$MINIMAX_API_KEY" --name minimax --no-tui
echo "→ MiniMax создан"

# Kimi K2.5
echo "--- Kimi ---"
cc-mirror quick --provider kimi --api-key "$KIMI_API_KEY" --name kimi --no-tui
echo "→ Kimi создан"

echo ""
echo "=== 4. Настройка permissions ==="

# Нативный Claude — allow all + skip prompt
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ]; then
    # Обновляем существующий
    python3 -c "
import json
with open('$CLAUDE_SETTINGS') as f: d = json.load(f)
d.setdefault('permissions', {})['allow'] = ['*']
d['permissions']['deny'] = []
d['skipDangerousModePermissionPrompt'] = True
with open('$CLAUDE_SETTINGS', 'w') as f: json.dump(d, f, indent=2)
"
else
    mkdir -p "$HOME/.claude"
    cat > "$CLAUDE_SETTINGS" << 'SETTINGS'
{
  "env": {},
  "permissions": {
    "allow": ["*"],
    "deny": []
  },
  "skipDangerousModePermissionPrompt": true
}
SETTINGS
fi
echo "→ Claude нативный: permissions ok"

# MiniMax — allow all + skip prompt
MINIMAX_SETTINGS="$HOME/.cc-mirror/minimax/config/settings.json"
python3 -c "
import json
with open('$MINIMAX_SETTINGS') as f: d = json.load(f)
d['permissions'] = {'allow': ['*'], 'deny': []}
d['skipDangerousModePermissionPrompt'] = True
with open('$MINIMAX_SETTINGS', 'w') as f: json.dump(d, f, indent=2)
"
echo "→ MiniMax: permissions ok"

# Kimi — allow all + skip prompt
KIMI_SETTINGS="$HOME/.cc-mirror/kimi/config/settings.json"
python3 -c "
import json
with open('$KIMI_SETTINGS') as f: d = json.load(f)
d['permissions'] = {'allow': ['*'], 'deny': []}
d['skipDangerousModePermissionPrompt'] = True
with open('$KIMI_SETTINGS', 'w') as f: json.dump(d, f, indent=2)
"
echo "→ Kimi: permissions ok"

echo ""
echo "=== 5. Добавление алиасов в ~/.zshrc ==="

# Удаляем старые алиасы если есть
sed -i '' '/# Claude Code — провайдеры/d' ~/.zshrc 2>/dev/null || true
sed -i '' '/alias opus=/d' ~/.zshrc 2>/dev/null || true
sed -i '' '/alias kimi=.*dangerously/d' ~/.zshrc 2>/dev/null || true
sed -i '' '/alias max=.*dangerously/d' ~/.zshrc 2>/dev/null || true
sed -i '' '/alias cc=.*mclaude/d' ~/.zshrc 2>/dev/null || true
sed -i '' '/alias cm=.*minimax/d' ~/.zshrc 2>/dev/null || true
sed -i '' '/alias ck=.*kimi/d' ~/.zshrc 2>/dev/null || true

cat >> ~/.zshrc << 'ALIASES'

# Claude Code — провайдеры
alias opus="claude --model claude-opus-4-6 --dangerously-skip-permissions"       # Anthropic Opus 4.6
alias kimi="kimi --dangerously-skip-permissions"                                 # Kimi K2.5
alias max="minimax --dangerously-skip-permissions"                               # MiniMax M2.5
ALIASES
echo "→ Алиасы добавлены"

echo ""
echo "=== 6. Авторизация Anthropic ==="
echo "Запусти: claude"
echo "Пройди OAuth авторизацию один раз"

echo ""
echo "============================================"
echo "  ГОТОВО! Перезапусти терминал или выполни:"
echo "  source ~/.zshrc"
echo ""
echo "  Команды:"
echo "    opus  →  Anthropic Opus 4.6"
echo "    kimi  →  Kimi K2.5"
echo "    max   →  MiniMax M2.5"
echo "============================================"
