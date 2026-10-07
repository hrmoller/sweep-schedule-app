import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = AppModel()
    private let notificationDelegate = NotificationDelegate()
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var reviewWindow: NSWindow?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        notificationDelegate.onOpen = { [weak self] in self?.showReview() }

        setupStatusItem()
        model.setupLoginItemIfNeeded()
        startScheduler()
        Task { await model.preview() }
        openWindowsRequestedByEnvironment()
    }

    /// Development aid used for README screenshots:
    /// `SWEEP_SCHEDULE_SHOW=settings,review,menu open SweepSchedule.app` opens those on launch.
    private func openWindowsRequestedByEnvironment() {
        guard let value = ProcessInfo.processInfo.environment["SWEEP_SCHEDULE_SHOW"] else { return }
        let wanted = Set(value.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if wanted.contains("settings") { self.showSettings() }
            if wanted.contains("review") { self.showReview() }
            if let dir = Snapshots.directory {
                // Use a common-mode timer: menu tracking blocks the main queue, but not the run loop.
                let timer = Timer(timeInterval: 2.5, repeats: false) { _ in
                    // Called directly (not via Task) because the main dispatch queue is blocked while a menu is open.
                    MainActor.assumeIsolated { Snapshots.captureAllWindowsAndQuit(to: dir) }
                }
                RunLoop.main.add(timer, forMode: .common)
            }
            if wanted.contains("menu") { self.statusItem?.button?.performClick(nil) }
        }
    }

    // MARK: Scheduler

    /// Wakes every 15 minutes and after sleep; the model decides whether today's check is due.
    private func startScheduler() {
        let t = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.runIfDue() }
        }
        t.tolerance = 60
        timer = t

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)

        runIfDue()
    }

    @objc private func didWake() {
        // Give the system a moment to bring volumes and network back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            Task { @MainActor in self?.runIfDue() }
        }
    }

    private func runIfDue() {
        guard model.isDue() else { return }
        Task { await model.runCheck() }
    }

    // MARK: Status item and menu

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateIcon(pendingCount: 0)

        model.$pending
            .receive(on: RunLoop.main)
            .sink { [weak self] pending in self?.updateIcon(pendingCount: pending.count) }
            .store(in: &cancellables)
    }

    private func updateIcon(pendingCount: Int) {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: pendingCount > 0 ? "trash.fill" : "trash",
                            accessibilityDescription: "Sweep Schedule")
        image?.isTemplate = true
        button.image = image
        button.title = pendingCount > 0 ? " \(pendingCount)" : ""
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: model.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if !model.notificationsOK {
            let warning = NSMenuItem(
                title: "Allow notifications in System Settings to enable deleting",
                action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(.separator())

        let n = model.pending.count
        let reviewTitle = n == 0 ? "Review Expiring Items…" : "Review \(n) Expiring Item\(n == 1 ? "" : "s")…"
        menu.addItem(makeItem(reviewTitle, #selector(showReviewAction), key: "r"))
        menu.addItem(makeItem("Check Now", #selector(checkNow), key: "k"))
        menu.addItem(.separator())
        menu.addItem(makeItem("Settings…", #selector(showSettingsAction), key: ","))
        menu.addItem(makeItem("Open History Log", #selector(openHistory)))
        menu.addItem(.separator())
        menu.addItem(makeItem("Quit Sweep Schedule", #selector(quit), key: "q"))
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func checkNow() { Task { await model.runCheck() } }
    @objc private func showReviewAction() { showReview() }
    @objc private func showSettingsAction() { showSettings() }
    @objc private func openHistory() { NSWorkspace.shared.open(model.historyURL) }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Windows

    func showReview() {
        Task { await model.preview() }
        present(&reviewWindow, title: "Expiring Items", size: NSSize(width: 620, height: 460)) {
            ReviewView(model: model)
        }
    }

    func showSettings() {
        present(&settingsWindow, title: "Sweep Schedule Settings", size: NSSize(width: 620, height: 480)) {
            SettingsView(model: model)
        }
    }

    private func present<V: View>(_ window: inout NSWindow?,
                                  title: String,
                                  size: NSSize,
                                  @ViewBuilder content: () -> V) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: content()))
            w.title = title
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(size)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
