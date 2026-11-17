import AppKit
import SwiftUI
import Combine

let SETTINGS_H: CGFloat = 580

final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: WidgetPanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private let spotify = SpotifyController()
    private let settings = Settings()
    private var cancellables = Set<AnyCancellable>()
    private let originKey = "widgetOrigin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildStatusItem()

        // Any settings change re-applies size and window level.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)

        if settings.isFirstRun { openSettings() }
    }

    // MARK: - Widget panel

    private func buildPanel() {
        let size = settings.widgetSize
        panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false            // the cards draw their own shadows
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.delegate = self

        let root = WidgetRoot(settings: settings, spotify: spotify,
                              onSettings: { [weak self] in self?.openSettings() })
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        applyLevel()
        restorePosition()
        panel.orderFrontRegardless()
    }

    private func applySettings() {
        applyLevel()
        let new = settings.widgetSize
        if panel.frame.size != new {
            // grow downward from the current top-left corner
            let top = panel.frame.maxY
            panel.setContentSize(new)
            panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x, y: top - new.height))
            panel.contentView?.frame = NSRect(origin: .zero, size: new)
            saveOrigin()
        }
        panel.orderFrontRegardless()
    }

    private func applyLevel() {
        panel.level = settings.pinnedToDesktop
            ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            : .floating
    }

    private func restorePosition() {
        if let saved = UserDefaults.standard.string(forKey: originKey) {
            let p = NSPointFromString(saved)
            let frame = NSRect(origin: p, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
                panel.setFrameOrigin(p)
                return
            }
        }
        resetPositionValue()
    }

    private func resetPositionValue() {
        guard let screen = NSScreen.main else { return }
        let v = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: v.maxX - panel.frame.width - 40,
                                     y: v.midY - panel.frame.height / 2))
        saveOrigin()
    }

    private func saveOrigin() {
        UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: originKey)
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel else { return }
        saveOrigin()
    }

    // MARK: - Settings window

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, spotify: spotify,
                                    onResetPosition: { [weak self] in self?.resetPositionValue() })
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: SETTINGS_H),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.contentMinSize = NSSize(width: 720, height: 460)
            w.title = "Vinyl Widget"
            w.contentView = NSHostingView(rootView: view)
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "opticaldisc",
                                          accessibilityDescription: "Vinyl Widget")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Customize…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Sit on Wallpaper", action: #selector(togglePinned), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Compact Mode", action: #selector(toggleCompact), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Show / Hide Widget", action: #selector(toggleWidget), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Reset Position", action: #selector(resetPosition), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Spotify", action: #selector(openSpotify), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Vinyl Widget", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func togglePinned() { settings.pinnedToDesktop.toggle() }

    @objc private func toggleCompact() { settings.compactMode.toggle() }

    @objc private func toggleWidget() {
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func resetPosition() {
        resetPositionValue()
        panel.orderFrontRegardless()
    }

    @objc private func openSpotify() { spotify.activateSpotify() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.title == "Sit on Wallpaper" })?.state =
            settings.pinnedToDesktop ? .on : .off
        menu.items.first(where: { $0.title == "Compact Mode" })?.state =
            settings.compactMode ? .on : .off
    }
}

// Retained for the lifetime of the process (NSApp holds its delegate weakly).
var sharedDelegate: AppDelegate?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    sharedDelegate = delegate
    app.delegate = delegate
    app.run()
}
