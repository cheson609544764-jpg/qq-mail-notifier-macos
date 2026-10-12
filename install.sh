#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_APP="$SCRIPT_DIR/build/QQMail Notifier.app"
INSTALL_ROOT="$HOME/Applications"
INSTALLED_APP="$INSTALL_ROOT/QQMail Notifier.app"
LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
PLIST_PATH="$LAUNCH_AGENTS/local.qqmail.notifier.plist"
SUPPORT_DIR="$HOME/Library/Application Support/QQMailNotifier"
LABEL="local.qqmail.notifier"
DOMAIN="gui/$(id -u)"

if [[ ! -d "$SOURCE_APP" ]]; then
  "$SCRIPT_DIR/build.sh"
fi

mkdir -p "$INSTALL_ROOT" "$LAUNCH_AGENTS" "$SUPPORT_DIR"
chmod 700 "$SUPPORT_DIR"

/bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
/usr/bin/ditto "$SOURCE_APP" "$INSTALLED_APP"

PLIST_TEMPLATE="$SCRIPT_DIR/launch-agent.plist.template"
/usr/bin/sed \
  -e "s|__EXECUTABLE__|$INSTALLED_APP/Contents/MacOS/QQMailNotifier|g" \
  -e "s|__STDOUT__|$SUPPORT_DIR/app.log|g" \
  -e "s|__STDERR__|$SUPPORT_DIR/app-error.log|g" \
  "$PLIST_TEMPLATE" > "$PLIST_PATH"
chmod 600 "$PLIST_PATH"

/bin/launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
echo "安装完成。菜单栏将出现信封图标。"
