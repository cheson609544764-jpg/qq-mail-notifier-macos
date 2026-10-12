#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/build"
APP_DIR="$BUILD_DIR/QQMail Notifier.app"
CONTENTS_DIR="$APP_DIR/Contents"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$SCRIPT_DIR/src/qqmail_check.py" "$CONTENTS_DIR/Resources/qqmail_check.py"
chmod 700 "$CONTENTS_DIR/Resources/qqmail_check.py"

/usr/bin/swiftc \
  -O \
  -parse-as-library \
  -framework AppKit \
  -framework Foundation \
  -framework Security \
  -framework UserNotifications \
  "$SCRIPT_DIR/src/QQMailNotifier.swift" \
  -o "$CONTENTS_DIR/MacOS/QQMailNotifier"

/usr/bin/codesign --force --deep --sign - "$APP_DIR"
echo "构建完成：$APP_DIR"
