import AppKit
import Foundation

enum DisplayMode: String {
    case quotaOnly
    case quotaAndReset
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let displayModeKey = "displayMode"
    private(set) var displayMode = DisplayMode(
        rawValue: UserDefaults.standard.string(forKey: displayModeKey) ?? ""
    ) ?? .quotaOnly
    private(set) var snapshot: UsageSnapshot?
    private(set) var errorMessage: String?
    private(set) var isRefreshing = false
    private(set) var statusItem: NSStatusItem?
    private var timer: Timer?
    private let client = CodexUsageClient()
    private let fiveHourItem = NSMenuItem()
    private let fiveHourResetItem = NSMenuItem()
    private let weeklyItem = NSMenuItem()
    private let weeklyResetItem = NSMenuItem()
    private let syncItem = NSMenuItem()
    private let errorItem = NSMenuItem()
    private let quotaOnlyItem = NSMenuItem(title: "仅显示额度", action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
    private let quotaAndResetItem = NSMenuItem(title: "额度 + 重置时间", action: #selector(changeDisplayMode(_:)), keyEquivalent: "")
    private let refreshItem = NSMenuItem(title: "立即同步", action: #selector(refresh(_:)), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        let timer = Timer(timeInterval: 60, target: self, selector: #selector(refresh(_:)), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refresh(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    func configureStatusItem() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in [fiveHourItem, fiveHourResetItem, weeklyItem, weeklyResetItem, syncItem, errorItem] {
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let displayMenu = NSMenu(title: "显示方式")
        displayMenu.autoenablesItems = false
        quotaOnlyItem.representedObject = DisplayMode.quotaOnly.rawValue
        quotaAndResetItem.representedObject = DisplayMode.quotaAndReset.rawValue
        for item in [quotaOnlyItem, quotaAndResetItem] {
            item.target = self
            displayMenu.addItem(item)
        }
        let displayItem = NSMenuItem(title: "显示方式", action: nil, keyEquivalent: "")
        displayItem.submenu = displayMenu
        menu.addItem(displayItem)
        refreshItem.target = self
        menu.addItem(refreshItem)
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        statusItem.menu = menu
        updateDisplay()
    }

    @objc func refresh(_ sender: Any?) {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshItem.isEnabled = false
        Task {
            do {
                finishRefresh(.success(try await client.fetch()))
            } catch {
                // 只显示受控的简短原因，避免把系统错误中的敏感内容带到 UI。
                finishRefresh(.failure(error as? UsageError ?? .network))
            }
        }
    }

    func finishRefresh(_ result: Result<UsageSnapshot, UsageError>) {
        isRefreshing = false
        switch result {
        case .success(let value):
            snapshot = value
            errorMessage = nil
        case .failure(let error):
            snapshot = nil
            errorMessage = error.localizedDescription
        }
        updateDisplay()
    }

    @objc func changeDisplayMode(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: value) else { return }
        displayMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.displayModeKey)
        updateDisplay()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateDisplay() {
        statusItem?.button?.title = Self.statusTitle(snapshot, mode: displayMode)
        fiveHourItem.title = "5 小时：剩余 \(snapshot?.fiveHour?.remainingText ?? "--%")"
        weeklyItem.title = "一周：剩余 \(snapshot?.weekly?.remainingText ?? "--%")"
        fiveHourResetItem.title = "重置：\(Self.dateText(snapshot?.fiveHour?.resetAt, format: "MM/dd HH:mm"))"
        weeklyResetItem.title = "重置：\(Self.dateText(snapshot?.weekly?.resetAt, format: "MM/dd HH:mm"))"
        syncItem.title = "最近同步：\(Self.dateText(snapshot?.syncedAt, format: "HH:mm"))"
        errorItem.title = errorMessage ?? ""
        errorItem.isHidden = errorMessage == nil
        quotaOnlyItem.state = displayMode == .quotaOnly ? .on : .off
        quotaAndResetItem.state = displayMode == .quotaAndReset ? .on : .off
        refreshItem.isEnabled = !isRefreshing
        statusItem?.button?.toolTip = [
            fiveHourItem.title,
            "重置：\(Self.dateText(snapshot?.fiveHour?.resetAt, format: "yyyy/MM/dd HH:mm:ss"))",
            weeklyItem.title,
            "重置：\(Self.dateText(snapshot?.weekly?.resetAt, format: "yyyy/MM/dd HH:mm:ss"))",
            syncItem.title,
            errorMessage
        ].compactMap { $0 }.joined(separator: "\n")
    }

    static func statusTitle(_ snapshot: UsageSnapshot?, mode: DisplayMode, now: Date = Date()) -> String {
        guard let snapshot else { return "⚡ 5h--% W--%" }
        var fiveHour = "5h\(snapshot.fiveHour?.remainingText ?? "--%")"
        var weekly = "W\(snapshot.weekly?.remainingText ?? "--%")"
        if mode == .quotaAndReset {
            let sameDay = snapshot.fiveHour?.resetAt.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? true
            fiveHour += " \(dateText(snapshot.fiveHour?.resetAt, format: sameDay ? "HH:mm" : "MM/dd HH:mm"))"
            weekly += " \(dateText(snapshot.weekly?.resetAt, format: "MM/dd"))"
        }
        return "⚡ \(fiveHour) \(weekly)"
    }

    static func dateText(_ date: Date?, format: String) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
