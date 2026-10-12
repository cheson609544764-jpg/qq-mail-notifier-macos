# QQ Mail Notifier for macOS / QQ 邮箱通知

中文 | [English](#english)

一个轻量的 macOS 原生菜单栏应用，通过 QQ 邮箱 IMAP 安全连接检查新邮件和未读邮件。

菜单栏信封图标会显示未读数量。点击图标可打开半透明磨砂列表，查看发件人、主题、邮件类型和简短摘要；点击邮件后会使用 Google Chrome 打开 QQ 邮箱网页端。应用也会为新邮件发送 macOS 原生通知。

## 功能

- 每分钟自动检查 QQ 邮箱，也支持手动刷新
- 菜单栏显示未读邮件数量
- 半透明磨砂弹窗，高度随未读邮件数量自动变化
- 展示最近 12 封未读邮件的发件人、主题、类型和摘要
- 本地分类：验证码、安全提醒、账单支付、工作事务、行程物流、推广订阅、普通邮件
- 点击邮件或系统通知后使用 Chrome 打开 QQ 邮箱
- 登录后自动启动，电脑睡眠恢复后继续检查
- 授权码存储在 macOS 钥匙串，不写入配置文件或日志
- 不发送邮件，不把邮件内容上传到第三方服务

## 系统要求

- macOS 13 或更高版本
- Google Chrome（未安装时使用系统默认浏览器）
- 已开启 IMAP/SMTP 的个人 QQ 邮箱
- 构建时需要 Apple Swift 编译器；运行时使用 macOS 自带的 Python 3

## 安装

1. 下载或克隆本项目。
2. 双击 `安装QQ邮箱通知.command`，或者在终端运行：

   ```zsh
   ./build.sh
   ./install.sh
   ```

3. 登录 QQ 邮箱网页，在“设置 → 账户/安全设置”中开启 IMAP/SMTP 并生成授权码。
4. 在本机配置窗口中输入完整 QQ 邮箱地址和授权码。
5. 首次运行时允许应用发送系统通知。

请勿把 QQ 邮箱授权码提交到 Git、聊天记录或普通文本文件中。

## 使用

- 点击菜单栏信封图标查看未读邮件。
- 点击邮件条目或“打开邮箱”，使用 Chrome 打开 QQ 邮箱网页端。
- 弹窗底部提供连接状态、设置和退出按钮。
- 新邮件通常会在一分钟内触发通知。

## 隐私与本地数据

授权码只保存在 macOS 钥匙串。配置文件只包含邮箱地址；运行状态会保存最后检查的 IMAP UID，以及菜单中当前显示邮件的本地摘要缓存。所有这些文件都位于用户自己的 Mac 上。

- 应用：`~/Applications/QQMail Notifier.app`
- 自动启动项：`~/Library/LaunchAgents/local.qqmail.notifier.plist`
- 本地配置、状态和日志：`~/Library/Application Support/QQMailNotifier/`

## 卸载

运行：

```zsh
./uninstall.sh
```

应用和自动启动项会移到废纸篓。为避免误删凭据，本地配置和钥匙串项目会保留；如需彻底删除，请在“钥匙串访问”中搜索 `local.qqmail.notifier.authorization-code` 并手动删除。

## 开发与测试

项目使用 Swift/AppKit、UserNotifications、Security.framework 和 Python 标准库，不依赖第三方运行时包。

```zsh
python3 -m unittest discover -s tests -v
./build.sh
```

---

## English

A lightweight native macOS menu-bar app that checks a personal QQ Mail account over a secure IMAP connection.

The envelope icon displays the unread count. Click it to open a translucent popover showing the sender, subject, category, and a short preview. Selecting a message opens QQ Mail in Google Chrome. New messages can also trigger native macOS notifications.

### Features

- Checks QQ Mail every minute, with manual refresh support
- Displays the unread count in the macOS menu bar
- Uses a translucent popover whose height adapts to the number of unread messages
- Shows the 12 most recent unread messages with sender, subject, category, and preview
- Local categories: verification code, security alert, billing/payment, work, travel/logistics, promotion/subscription, and general mail
- Opens QQ Mail in Chrome when a message or notification is clicked
- Starts automatically after login and resumes checking after wake
- Stores the IMAP authorization code in macOS Keychain—not in config files or logs
- Never sends mail or uploads message content to third-party services

### Requirements

- macOS 13 or later
- Google Chrome (falls back to the default browser when Chrome is unavailable)
- A personal QQ Mail account with IMAP/SMTP enabled
- Apple Swift compiler for building; the app uses the system Python 3 at runtime

### Installation

1. Download or clone this repository.
2. Double-click `安装QQ邮箱通知.command`, or run:

   ```zsh
   ./build.sh
   ./install.sh
   ```

3. Sign in to QQ Mail on the web, enable IMAP/SMTP under account or security settings, and generate an authorization code.
4. Enter the full QQ Mail address and authorization code in the local setup window.
5. Allow notification access when macOS asks.

Never commit your QQ Mail authorization code to Git or save it in chat logs or plain-text files.

### Usage

- Click the envelope icon in the menu bar to view unread messages.
- Click a message or **Open Mailbox** to open QQ Mail in Chrome.
- Connection status, refresh, settings, and quit controls are available in the popover.
- New-message notifications normally appear within one minute.

### Privacy and local data

The authorization code is stored only in macOS Keychain. The configuration file contains only the email address. Runtime state stores the last checked IMAP UID and a local preview cache for the messages currently shown in the popover. All data remains on the user's Mac.

- App: `~/Applications/QQMail Notifier.app`
- Login item: `~/Library/LaunchAgents/local.qqmail.notifier.plist`
- Local config, state, and logs: `~/Library/Application Support/QQMailNotifier/`

### Uninstall

Run:

```zsh
./uninstall.sh
```

The app and launch agent are moved to the Trash. Local configuration and the Keychain item are intentionally preserved to avoid accidental credential deletion. To remove the credential completely, search for `local.qqmail.notifier.authorization-code` in Keychain Access and delete it manually.

### Development and testing

The project uses Swift/AppKit, UserNotifications, Security.framework, and the Python standard library. No third-party runtime packages are required.

```zsh
python3 -m unittest discover -s tests -v
./build.sh
```
