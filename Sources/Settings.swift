import SwiftUI
import Combine

/// Everything the user can change, persisted to UserDefaults on every edit.
@MainActor
final class Settings: ObservableObject {
    @Published var theme: Theme { didSet { persist() } }
    @Published var scale: Double { didSet { persist() } }
    @Published var pinnedToDesktop: Bool { didSet { persist() } }
    @Published var spinRecord: Bool { didSet { persist() } }
    @Published var showTonearm: Bool { didSet { persist() } }
    @Published var showPanel: Bool { didSet { persist() } }
    @Published var compactMode: Bool { didSet { persist() } }

    private enum Key {
        static let theme = "theme"
        static let scale = "scale"
        static let pinned = "pinnedToDesktop"
        static let spin = "spinRecord"
        static let arm = "showTonearm"
        static let panel = "showPanel"
        static let compact = "compactMode"
        static let launched = "hasLaunchedBefore"
    }

    private let defaults = UserDefaults.standard
    private var loading = true

    /// False the very first time the app is ever run, so we can show settings once.
    let isFirstRun: Bool

    init() {
        defaults.register(defaults: [
            Key.scale: 1.0,
            Key.pinned: false,     // visible immediately on first run; opt in to wallpaper mode
            Key.spin: true,
            Key.arm: true,
            Key.panel: true,
            Key.compact: false,
        ])

        isFirstRun = !defaults.bool(forKey: Key.launched)
        defaults.set(true, forKey: Key.launched)

        if let data = defaults.data(forKey: Key.theme),
           let saved = try? JSONDecoder().decode(Theme.self, from: data) {
            theme = saved
        } else {
            theme = .default
        }
        scale = defaults.double(forKey: Key.scale)
        pinnedToDesktop = defaults.bool(forKey: Key.pinned)
        spinRecord = defaults.bool(forKey: Key.spin)
        showTonearm = defaults.bool(forKey: Key.arm)
        showPanel = defaults.bool(forKey: Key.panel)
        compactMode = defaults.bool(forKey: Key.compact)
        if scale < 0.6 || scale > 2.0 { scale = 1.0 }
        loading = false
    }

    private func persist() {
        guard !loading else { return }
        if let data = try? JSONEncoder().encode(theme) { defaults.set(data, forKey: Key.theme) }
        defaults.set(scale, forKey: Key.scale)
        defaults.set(pinnedToDesktop, forKey: Key.pinned)
        defaults.set(spinRecord, forKey: Key.spin)
        defaults.set(showTonearm, forKey: Key.arm)
        defaults.set(showPanel, forKey: Key.panel)
        defaults.set(compactMode, forKey: Key.compact)
    }

    func resetToDefaults() {
        theme = .default
        scale = 1.0
        spinRecord = true
        showTonearm = true
        showPanel = true
        compactMode = false
    }

    /// Widget size in points at the current scale.
    var baseHeight: CGFloat {
        compactMode ? basePanelH : (showPanel ? baseTotalH : basePlatterH)
    }

    var widgetSize: CGSize {
        CGSize(width: baseCardW * scale,
               height: baseHeight * scale)
    }
}
