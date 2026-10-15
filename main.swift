import AppKit

// 顶层入口在主线程执行，显式标注 AppKit 的主 actor 上下文。
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let appDelegate = AppDelegate()
    application.setActivationPolicy(.accessory)
    application.delegate = appDelegate
    withExtendedLifetime(appDelegate) {
        application.run()
    }
}
