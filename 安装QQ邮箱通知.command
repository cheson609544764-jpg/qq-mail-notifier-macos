#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
"$SCRIPT_DIR/build.sh"
"$SCRIPT_DIR/install.sh"
echo
echo "已经安装。请在弹出的窗口中输入 QQ 邮箱地址和 IMAP 授权码。"
echo "可以关闭这个终端窗口。"
