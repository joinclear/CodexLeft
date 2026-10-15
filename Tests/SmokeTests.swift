import AppKit
import Foundation

@main
enum SmokeTests {
    @MainActor
    static func main() throws {
        print("开始验证")
        fflush(stdout)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        // 独立测试可执行文件有独立的 defaults 域；不改应用设置。
        precondition(Bundle.main.bundleIdentifier != "com.joinclear.codexleft")
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppDelegate.displayModeKey)
        defer {
            if let previous { defaults.set(previous, forKey: AppDelegate.displayModeKey) }
            else { defaults.removeObject(forKey: AppDelegate.displayModeKey) }
        }
        defaults.removeObject(forKey: AppDelegate.displayModeKey)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        }
        let now = date(15, 12, 35)
        let fiveHourReset = date(15, 13, 16)
        let weeklyReset = date(20, 9, 0)

        func window(_ seconds: Double, _ used: Double, _ reset: Date) -> [String: Any] {
            ["limit_window_seconds": seconds, "used_percent": used, "reset_at": reset.timeIntervalSince1970]
        }
        func data(_ primary: Any = NSNull(), _ secondary: Any = NSNull()) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["rate_limit": [
                "primary_window": primary, "secondary_window": secondary
            ]])
        }
        func expectError(_ body: () throws -> Void, matching: (UsageError) -> Bool) {
            do {
                try body()
                preconditionFailure("应返回错误")
            } catch {
                precondition((error as? UsageError).map(matching) == true, "错误类型不符")
            }
        }

        // 故意把一周放在 primary，5 小时放在 secondary。
        let fixture = try data(window(604_800, 20, weeklyReset), window(18_000, 23, fiveHourReset))
        let parsed = try CodexUsageClient.parse(fixture)
        precondition(parsed.fiveHour?.remainingPercent == 77)
        precondition(parsed.weekly?.remainingPercent == 80)
        precondition(parsed.fiveHour?.resetAt == fiveHourReset)
        precondition(parsed.weekly?.resetAt == weeklyReset)
        for seconds in [14_400.0, 21_600.0] {
            let value = try CodexUsageClient.parse(data(window(seconds, 23, fiveHourReset)))
            precondition(value.fiveHour != nil)
        }
        for seconds in [518_400.0, 691_200.0] {
            let value = try CodexUsageClient.parse(data(window(seconds, 20, weeklyReset)))
            precondition(value.weekly != nil)
        }
        for seconds in [14_399.0, 21_601.0, 518_399.0, 691_201.0] {
            let value = try CodexUsageClient.parse(data(window(seconds, 23, fiveHourReset), window(604_800, 20, weeklyReset)))
            precondition(value.fiveHour == nil)
        }
        let weeklyOnly = try CodexUsageClient.parse(data(window(604_800, 20, weeklyReset)))
        precondition(weeklyOnly.fiveHour == nil)
        precondition(AppDelegate.statusTitle(weeklyOnly, mode: .quotaOnly, now: now) == "⚡ 5h--% W80%")
        let fiveOnly = try CodexUsageClient.parse(data(window(18_000, 0, fiveHourReset)))
        precondition(fiveOnly.weekly == nil)
        precondition(AppDelegate.statusTitle(fiveOnly, mode: .quotaOnly, now: now) == "⚡ 5h100% W--%")
        let missingFields = try CodexUsageClient.parse(data(["limit_window_seconds": 18_000]))
        precondition(missingFields.fiveHour?.remainingPercent == nil)
        precondition(missingFields.fiveHour?.resetAt == nil)
        precondition(AppDelegate.statusTitle(missingFields, mode: .quotaAndReset, now: now) == "⚡ 5h--% -- W--% --")
        precondition(UsageWindow(usedPercent: -5, resetAt: nil).remainingPercent == 100)
        precondition(UsageWindow(usedPercent: 105, resetAt: nil).remainingPercent == 0)
        precondition(UsageWindow(usedPercent: 23.6, resetAt: nil).remainingPercent == 76)
        expectError({ _ = try CodexUsageClient.parse(Data("invalid".utf8)) }, matching: {
            if case .invalidResponse = $0 { return true }; return false
        })
        expectError({ _ = try CodexUsageClient.parse(data()) }, matching: {
            if case .noWindows = $0 { return true }; return false
        })
        expectError({
            _ = try CodexUsageClient.parse(Data(#"{"rate_limit":{"primary_window":{"used_percent":"bad"}}}"#.utf8))
        }, matching: { if case .invalidResponse = $0 { return true }; return false })
        print("通过：窗口分类、边界、缺失值、整数取整、异常数据")

        let snapshot = UsageSnapshot(fiveHour: parsed.fiveHour, weekly: parsed.weekly, syncedAt: now)
        precondition(AppDelegate.statusTitle(snapshot, mode: .quotaOnly, now: now) == "⚡ 5h77% W80%")
        precondition(AppDelegate.statusTitle(snapshot, mode: .quotaAndReset, now: now) == "⚡ 5h77% 13:16 W80% 10/20")
        let tomorrow = UsageSnapshot(
            fiveHour: UsageWindow(usedPercent: 23, resetAt: date(16, 1, 16)), weekly: parsed.weekly, syncedAt: now
        )
        precondition(AppDelegate.statusTitle(tomorrow, mode: .quotaAndReset, now: now) == "⚡ 5h77% 10/16 01:16 W80% 10/20")
        // 过了重置时间也仍用服务端额度，不自行补满。
        precondition(AppDelegate.statusTitle(snapshot, mode: .quotaOnly, now: date(21, 0, 0)) == "⚡ 5h77% W80%")
        print("通过：两种显示格式、跨日、本地重置时间、不推算额度")

        let delegate = AppDelegate()
        precondition(delegate.displayMode == .quotaOnly)
        delegate.configureStatusItem()
        delegate.finishRefresh(.success(snapshot))
        let button = delegate.statusItem!.button!
        let menu = delegate.statusItem!.menu!
        precondition(button.title == "⚡ 5h77% W80%")
        precondition(button.toolTip!.contains("2026/10/15 13:16:00"))
        precondition(button.toolTip!.contains("2026/10/20 09:00:00"))
        precondition(menu.items[1].title == "重置：10/15 13:16")
        precondition(menu.items[4].title == "最近同步：12:35")
        let displayMenu = menu.items.first { $0.title == "显示方式" }!.submenu!
        precondition(displayMenu.items[0].state == .on)
        displayMenu.performActionForItem(at: 1)
        precondition(delegate.displayMode == .quotaAndReset)
        precondition(button.title == AppDelegate.statusTitle(snapshot, mode: .quotaAndReset))
        precondition(displayMenu.items[1].state == .on && displayMenu.items[0].state == .off)
        precondition(!delegate.isRefreshing && delegate.snapshot?.syncedAt == now)
        precondition(defaults.string(forKey: AppDelegate.displayModeKey) == DisplayMode.quotaAndReset.rawValue)
        precondition(AppDelegate().displayMode == .quotaAndReset)
        displayMenu.performActionForItem(at: 0)
        precondition(button.title == "⚡ 5h77% W80%")
        precondition(AppDelegate().displayMode == .quotaOnly)
        print("通过：原生菜单切换、选中状态、立即显示、UserDefaults 恢复")

        let httpFailure = HTTPURLResponse(
            url: URL(string: "https://example.invalid/usage")!, statusCode: 503, httpVersion: nil, headerFields: nil
        )!
        let httpSuccess = HTTPURLResponse(
            url: URL(string: "https://example.invalid/usage")!, statusCode: 200, httpVersion: nil, headerFields: nil
        )!
        let successfulResponse = try CodexUsageClient.parseResponse(fixture, response: httpSuccess)
        precondition(successfulResponse.fiveHour?.remainingPercent == 77)
        // 同一条错误出口验证 HTTP 失败及解析失败都会清空旧值。
        for response in [httpFailure, httpSuccess] {
            do {
                _ = try CodexUsageClient.parseResponse(Data("invalid".utf8), response: response)
                preconditionFailure("应返回错误")
            } catch let error as UsageError {
                delegate.finishRefresh(.failure(error))
            }
            precondition(delegate.snapshot == nil)
            precondition(button.title == "⚡ 5h--% W--%")
            precondition(menu.items[0].title == "5 小时：剩余 --%")
            precondition(menu.items[2].title == "一周：剩余 --%")
            precondition(menu.items[4].title == "最近同步：--")
            precondition(!menu.items[5].isHidden && delegate.errorMessage != nil)
            displayMenu.performActionForItem(at: 1)
            precondition(button.title == "⚡ 5h--% W--%")
            delegate.finishRefresh(.success(snapshot))
            precondition(delegate.errorMessage == nil && menu.items[5].isHidden)
            precondition(!delegate.isRefreshing)
        }
        delegate.finishRefresh(.failure(.timeout))
        precondition(button.title == "⚡ 5h--% W--%" && menu.items[5].title == "请求超时")
        NSStatusBar.system.removeStatusItem(delegate.statusItem!)
        print("通过：HTTP/解析/超时失败清空、错误原因、失败后恢复")
        print("全部验证通过（模拟数据，无真实凭据及网络请求）")
    }
}
