import AppKit
import Foundation
import Security
import UserNotifications

private let bundleIdentifier = "local.qqmail.notifier"
private let keychainService = "local.qqmail.notifier.authorization-code"
private let qqMailURL = URL(string: "https://mail.qq.com/")!

private func appLog(_ message: String) {
    let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

private struct Configuration: Codable {
    let email: String
}

private struct MailItem: Decodable {
    let uid: Int
    let subject: String
    let sender: String
    let snippet: String
    let category: String
}

private struct CheckResult: Decodable {
    let ok: Bool
    let initialized: Bool?
    let newMails: [MailItem]?
    let unreadMails: [MailItem]?
    let unreadTotal: Int?
    let skipped: Int?
    let failed: Int?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, initialized, skipped, failed, error
        case newMails = "new"
        case unreadMails = "unread"
        case unreadTotal = "unread_total"
    }
}

private final class UnreadMailCellView: NSTableCellView {
    private let senderLabel = NSTextField(labelWithString: "")
    private let subjectLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        senderLabel.font = .boldSystemFont(ofSize: 12)
        senderLabel.textColor = .secondaryLabelColor
        senderLabel.lineBreakMode = .byTruncatingTail
        subjectLabel.font = .systemFont(ofSize: 13, weight: .medium)
        subjectLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = .secondaryLabelColor
        snippetLabel.maximumNumberOfLines = 2
        snippetLabel.lineBreakMode = .byTruncatingTail

        for label in [senderLabel, subjectLabel, snippetLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            senderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            senderLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            senderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            subjectLabel.leadingAnchor.constraint(equalTo: senderLabel.leadingAnchor),
            subjectLabel.trailingAnchor.constraint(equalTo: senderLabel.trailingAnchor),
            subjectLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 3),
            snippetLabel.leadingAnchor.constraint(equalTo: senderLabel.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: senderLabel.trailingAnchor),
            snippetLabel.topAnchor.constraint(equalTo: subjectLabel.bottomAnchor, constant: 3),
            snippetLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -7),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with mail: MailItem) {
        senderLabel.stringValue = mail.sender
        subjectLabel.stringValue = "[\(mail.category)] \(mail.subject)"
        snippetLabel.stringValue = mail.snippet.isEmpty ? "（暂无摘要）" : mail.snippet
        toolTip = "点击后在 Chrome 中打开 QQ 邮箱"
    }
}

private final class UnreadPopoverViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let countLabel = NSTextField(labelWithString: "正在读取未读邮件…")
    private let statusLabel = NSTextField(labelWithString: "正在启动…")
    private var mails: [MailItem] = []
    private let refreshHandler: () -> Void
    private let openHandler: () -> Void
    private let configureHandler: () -> Void
    private let quitHandler: () -> Void

    init(
        refreshHandler: @escaping () -> Void,
        openHandler: @escaping () -> Void,
        configureHandler: @escaping () -> Void,
        quitHandler: @escaping () -> Void
    ) {
        self.refreshHandler = refreshHandler
        self.openHandler = openHandler
        self.configureHandler = configureHandler
        self.quitHandler = quitHandler
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 420, height: 175)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .popover
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        view = root

        let titleLabel = NSTextField(labelWithString: "QQ 邮箱未读")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .roundRect
        refreshButton.controlSize = .small
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        let openButton = NSButton(title: "打开邮箱", target: self, action: #selector(openMailbox))
        openButton.bezelStyle = .roundRect
        openButton.controlSize = .small
        openButton.translatesAutoresizingMaskIntoConstraints = false

        let configureButton = NSButton(title: "设置", target: self, action: #selector(configureMailbox))
        configureButton.bezelStyle = .roundRect
        configureButton.controlSize = .small
        configureButton.translatesAutoresizingMaskIntoConstraints = false

        let quitButton = NSButton(title: "退出", target: self, action: #selector(quitApplication))
        quitButton.bezelStyle = .roundRect
        quitButton.controlSize = .small
        quitButton.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mail"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 83
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = .separatorColor
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = tableView

        root.addSubview(titleLabel)
        root.addSubview(countLabel)
        root.addSubview(refreshButton)
        root.addSubview(openButton)
        root.addSubview(configureButton)
        root.addSubview(quitButton)
        root.addSubview(statusLabel)
        root.addSubview(scrollView)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 13),
            countLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            countLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            openButton.trailingAnchor.constraint(equalTo: refreshButton.leadingAnchor, constant: -8),
            openButton.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            refreshButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -9),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: configureButton.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: configureButton.leadingAnchor, constant: -8),
            quitButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            quitButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            configureButton.trailingAnchor.constraint(equalTo: quitButton.leadingAnchor, constant: -7),
            configureButton.centerYAnchor.constraint(equalTo: quitButton.centerYAnchor),
        ])
    }

    @discardableResult
    func update(mails: [MailItem], total: Int) -> NSSize {
        self.mails = mails
        if total == 0 {
            countLabel.stringValue = "当前没有未读邮件"
        } else if total > mails.count {
            countLabel.stringValue = "共 \(total) 封未读 · 显示最近 \(mails.count) 封"
        } else {
            countLabel.stringValue = "共 \(total) 封未读"
        }
        tableView.deselectAll(nil)
        tableView.reloadData()
        let visibleRows = min(max(mails.count, 1), 5)
        let listHeight: CGFloat = mails.isEmpty ? 56 : CGFloat(visibleRows) * 83
        let size = NSSize(width: 420, height: min(530, 119 + listHeight))
        preferredContentSize = size
        return size
    }

    func showError(_ message: String) {
        countLabel.stringValue = message
    }

    func updateStatus(_ message: String) {
        statusLabel.stringValue = message
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        max(1, mails.count)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        mails.isEmpty ? 56 : 83
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if mails.isEmpty {
            let identifier = NSUserInterfaceItemIdentifier("empty")
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
                return reused
            }
            let label = NSTextField(wrappingLabelWithString: "没有未读邮件")
            label.identifier = identifier
            label.alignment = .center
            label.textColor = .secondaryLabelColor
            return label
        }

        let identifier = NSUserInterfaceItemIdentifier("mail-cell")
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? UnreadMailCellView)
            ?? UnreadMailCellView(frame: .zero)
        cell.identifier = identifier
        cell.configure(with: mails[row])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < mails.count else { return }
        openHandler()
        tableView.deselectAll(nil)
    }

    @objc private func refresh() {
        countLabel.stringValue = "正在刷新…"
        refreshHandler()
    }

    @objc private func openMailbox() {
        openHandler()
    }

    @objc private func configureMailbox() {
        configureHandler()
    }

    @objc private func quitApplication() {
        quitHandler()
    }
}

private enum KeychainFailure: LocalizedError {
    case operation(OSStatus)

    var errorDescription: String? {
        switch self {
        case .operation(let status):
            return "钥匙串操作失败（\(status)）。"
        }
    }
}

@main
private enum QQMailNotifierMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private var statusPopover: NSPopover!
    private var unreadPopoverController: UnreadPopoverViewController!
    private var timer: Timer?
    private var isChecking = false
    private var isShowingConfiguration = false
    private var configuredEmail: String?
    private var lastErrorNotificationAt: Date?
    private var currentStatus = "正在启动…"
    private var currentUnreadTotal = 0

    private var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/QQMailNotifier", isDirectory: true)
    }

    private var configURL: URL { supportDirectory.appendingPathComponent("config.json") }
    private var stateURL: URL { supportDirectory.appendingPathComponent("state.json") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        appLog("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        createSupportDirectory()
        configureStatusItem()
        configureNotifications()
        configuredEmail = loadConfiguration()?.email

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkForMail()
        }
        RunLoop.main.add(timer!, forMode: .common)

        if configuredEmail == nil {
            appLog("no configuration; scheduling setup window")
            setStatus("尚未配置")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showConfiguration()
            }
        } else {
            requestNotificationPermission()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.checkForMail()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if configuredEmail == nil {
            DispatchQueue.main.async { [weak self] in
                self?.showConfiguration()
            }
        } else {
            showUnreadPopover()
        }
        return true
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "QQ 邮箱未读")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.toolTip = "QQ 邮箱通知"
            button.target = self
            button.action = #selector(toggleUnreadPopover)
            button.sendAction(on: [.leftMouseUp])
        }

        unreadPopoverController = UnreadPopoverViewController(
            refreshHandler: { [weak self] in self?.checkForMail() },
            openHandler: { [weak self] in
                self?.statusPopover.performClose(nil)
                self?.openInChrome(qqMailURL)
            },
            configureHandler: { [weak self] in
                self?.statusPopover.performClose(nil)
                self?.showConfiguration()
            },
            quitHandler: { [weak self] in
                self?.statusPopover.performClose(nil)
                NSApp.terminate(self)
            }
        )
        statusPopover = NSPopover()
        statusPopover.behavior = .transient
        statusPopover.animates = true
        statusPopover.contentSize = unreadPopoverController.preferredContentSize
        statusPopover.contentViewController = unreadPopoverController
    }

    private func configureNotifications() {
        let openAction = UNNotificationAction(identifier: "OPEN_QQMAIL", title: "打开邮箱", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: "QQMAIL_NEW_MAIL",
            actions: [openAction],
            intentIdentifiers: [],
            options: []
        )
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.setStatus("通知权限错误：\(error.localizedDescription)")
                } else if !granted {
                    self?.setStatus("通知权限未开启")
                }
            }
        }
    }

    private func createSupportDirectory() {
        try? FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    private func loadConfiguration() -> Configuration? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(Configuration.self, from: data)
    }

    private func saveConfiguration(email: String) throws {
        createSupportDirectory()
        let data = try JSONEncoder().encode(Configuration(email: email))
        try data.write(to: configURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func saveAuthorizationCode(_ code: String, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecValueData as String] = Data(code.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainFailure.operation(status) }
    }

    private func loadAuthorizationCode(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainFailure.operation(status)
        }
        return value
    }

    private func deleteAuthorizationCode(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    @objc private func configureMailbox() {
        showConfiguration()
    }

    private func showConfiguration() {
        guard !isShowingConfiguration else { return }
        isShowingConfiguration = true
        defer {
            isShowingConfiguration = false
            NSApp.setActivationPolicy(.accessory)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        appLog("presenting setup window; activationPolicy=\(NSApp.activationPolicy().rawValue)")

        let emailField = NSTextField(string: configuredEmail ?? "")
        emailField.placeholderString = "例如：123456@qq.com"
        let codeField = NSSecureTextField(string: "")
        codeField.placeholderString = "QQ 邮箱生成的授权码（不是登录密码）"

        let emailLabel = NSTextField(labelWithString: "QQ 邮箱地址")
        let codeLabel = NSTextField(labelWithString: "IMAP 授权码")
        let helpLabel = NSTextField(wrappingLabelWithString: "授权码仅存入这台 Mac 的钥匙串。QQ 邮箱网页：设置 → 账户/安全设置 → 开启 IMAP/SMTP → 生成授权码。")
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.font = .systemFont(ofSize: 11)

        let stack = NSStackView(views: [emailLabel, emailField, codeLabel, codeField, helpLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        stack.frame = NSRect(x: 0, y: 0, width: 430, height: 145)
        emailField.widthAnchor.constraint(equalToConstant: 430).isActive = true
        codeField.widthAnchor.constraint(equalToConstant: 430).isActive = true
        helpLabel.widthAnchor.constraint(equalToConstant: 430).isActive = true

        let alert = NSAlert()
        alert.messageText = "配置 QQ 邮箱通知"
        alert.informativeText = "保存后会先记录当前收件箱位置，只通知之后到达的新邮件。"
        alert.alertStyle = .informational
        alert.accessoryView = stack
        alert.addButton(withTitle: "保存并开始")
        alert.addButton(withTitle: "打开 QQ 邮箱")
        alert.addButton(withTitle: "稍后")
        alert.window.level = .modalPanel
        alert.window.collectionBehavior = [.moveToActiveSpace]
        alert.window.center()

        let response = alert.runModal()
        appLog("setup window closed; response=\(response.rawValue)")
        if response == .alertSecondButtonReturn {
            openInChrome(qqMailURL)
            return
        }
        guard response == .alertFirstButtonReturn else { return }

        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let code = codeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.contains("."), code.count >= 8 else {
            showMessage(title: "信息不完整", text: "请输入完整的 QQ 邮箱地址，以及网页端生成的 IMAP 授权码。")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.showConfiguration() }
            return
        }

        do {
            let previousEmail = configuredEmail
            try saveAuthorizationCode(code, account: email)
            try saveConfiguration(email: email)
            if previousEmail != email {
                try? FileManager.default.removeItem(at: stateURL)
                if let previousEmail = previousEmail {
                    deleteAuthorizationCode(account: previousEmail)
                }
            }
            configuredEmail = email
            requestNotificationPermission()
            setStatus("已配置，正在连接…")
            showUnreadPopover()
            checkForMail()
        } catch {
            showMessage(title: "保存失败", text: error.localizedDescription)
        }
    }

    private func showMessage(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func checkNow() {
        checkForMail()
    }

    private func checkForMail() {
        guard !isChecking else { return }
        guard let email = configuredEmail else {
            setStatus("尚未配置")
            return
        }

        let code: String
        do {
            code = try loadAuthorizationCode(account: email)
        } catch {
            appLog("authorization code unavailable in Keychain")
            setStatus("授权码不可用，请重新配置")
            return
        }

        guard let checker = Bundle.main.resourceURL?.appendingPathComponent("qqmail_check.py"),
              FileManager.default.fileExists(atPath: checker.path) else {
            setStatus("缺少邮件检查组件")
            return
        }

        isChecking = true
        appLog("starting IMAP check")
        setStatus("正在检查新邮件…")

        let outputPipe = Pipe()
        let inputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [checker.path, "--email", email, "--state", stateURL.path]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        process.environment = ProcessInfo.processInfo.environment.merging(["PYTHONIOENCODING": "utf-8"]) { _, new in new }

        process.terminationHandler = { [weak self] _ in
            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                self?.finishCheck(output: output)
            }
        }

        do {
            try process.run()
            if let input = (code + "\n").data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(input)
            }
            try? inputPipe.fileHandleForWriting.close()
        } catch {
            isChecking = false
            appLog("unable to start checker process")
            setStatus("无法启动邮件检查：\(error.localizedDescription)")
        }
    }

    private func finishCheck(output: Data) {
        isChecking = false

        guard let result = try? JSONDecoder().decode(CheckResult.self, from: output) else {
            appLog("checker returned invalid JSON")
            setStatus("邮件检查返回了无效结果")
            return
        }
        guard result.ok else {
            let message = result.error ?? "检查邮件失败，稍后会自动重试。"
            appLog("IMAP check failed: \(message)")
            setStatus(message)
            unreadPopoverController.showError(message)
            maybeNotifyError(message)
            return
        }

        let unread = result.unreadMails ?? []
        let unreadTotal = result.unreadTotal ?? unread.count
        currentUnreadTotal = unreadTotal
        statusPopover.contentSize = unreadPopoverController.update(mails: unread, total: unreadTotal)
        updateStatusItemCount(unreadTotal)

        if result.initialized == true {
            appLog("IMAP baseline initialized")
            setStatus("监听中 · 每 1 分钟检查")
            deliverSystemNotice(title: "QQ 邮箱通知已开始", body: "只会通知从现在起收到的新邮件。")
            return
        }

        let mails = result.newMails ?? []
        appLog("IMAP check succeeded; newCount=\(mails.count)")
        if mails.isEmpty {
            setStatus("监听中 · 刚刚检查")
        } else {
            for mail in mails {
                deliverMailNotification(mail)
            }
            var status = "已通知 \(mails.count) 封新邮件"
            if let skipped = result.skipped, skipped > 0 {
                status += "（另有 \(skipped) 封）"
            }
            setStatus(status)
        }
    }

    private func deliverMailNotification(_ mail: MailItem) {
        let content = UNMutableNotificationContent()
        content.title = "[\(mail.category)] \(mail.subject)"
        content.subtitle = mail.sender
        content.body = mail.snippet.isEmpty ? "点击后在 Chrome 中打开 QQ 邮箱" : mail.snippet
        content.sound = .default
        content.categoryIdentifier = "QQMAIL_NEW_MAIL"
        content.userInfo = ["url": qqMailURL.absoluteString]
        let request = UNNotificationRequest(identifier: "qqmail-\(mail.uid)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func deliverSystemNotice(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": qqMailURL.absoluteString]
        let request = UNNotificationRequest(identifier: "qqmail-ready-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func maybeNotifyError(_ message: String) {
        if let last = lastErrorNotificationAt, Date().timeIntervalSince(last) < 4 * 60 * 60 {
            return
        }
        lastErrorNotificationAt = Date()
        let content = UNMutableNotificationContent()
        content.title = "QQ 邮箱通知需要处理"
        content.body = message
        let request = UNNotificationRequest(identifier: "qqmail-error", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func setStatus(_ value: String) {
        currentStatus = value
        unreadPopoverController?.updateStatus(value)
        statusItem?.button?.toolTip = "QQ 邮箱通知 · \(value)"
    }

    private func updateStatusItemCount(_ count: Int) {
        guard let button = statusItem.button else { return }
        button.title = count > 0 ? " \(count)" : ""
        let symbol = count > 0 ? "envelope.badge.fill" : "envelope"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "QQ 邮箱未读 \(count) 封")
        image?.isTemplate = true
        button.image = image
    }

    @objc private func toggleUnreadPopover() {
        if statusPopover.isShown {
            statusPopover.performClose(nil)
        } else {
            showUnreadPopover()
        }
    }

    private func showUnreadPopover() {
        guard let button = statusItem.button else { return }
        unreadPopoverController.updateStatus(currentStatus)
        statusPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openQQMail() {
        openInChrome(qqMailURL)
    }

    private func openInChrome(_ url: URL) {
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        if FileManager.default.fileExists(atPath: chrome.path) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: configuration)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(supportDirectory)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier || response.actionIdentifier == "OPEN_QQMAIL" {
            openInChrome(qqMailURL)
        }
        completionHandler()
    }
}
