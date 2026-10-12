#!/bin/zsh
set -euo pipefail

LABEL="local.qqmail.notifier"
DOMAIN="gui/$(id -u)"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALLED_APP="$HOME/Applications/QQMail Notifier.app"

/bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
[[ -f "$PLIST_PATH" ]] && /bin/mv "$PLIST_PATH" "$HOME/.Trash/"
[[ -d "$INSTALLED_APP" ]] && /bin/mv "$INSTALLED_APP" "$HOME/.Trash/"

echo "应用和开机启动项已移到废纸篓。邮箱配置和钥匙串授权码仍保留。"
