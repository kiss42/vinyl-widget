import SwiftUI
import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var spotify: SpotifyController
    var onResetPosition: () -> Void

    @State private var loginAtStart = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            preview
            Divider()
            controls
        }
        .frame(minWidth: 720, minHeight: 460)
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 14) {
            Text("Preview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            WidgetRoot(settings: settings, spotify: spotify, interactive: false)
                .scaleEffect(0.78 / max(settings.scale, 0.01))
                .frame(width: baseCardW * 0.78,
                       height: settings.baseHeight * 0.78)

            Spacer(minLength: 0)

            Text(spotify.state.running
                 ? "Showing what’s playing right now"
                 : "Start playing something in Spotify to see it here")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 220)
        }
        .padding(24)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
    }

    // MARK: Controls

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Theme") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                              spacing: 10) {
                        ForEach(Theme.presets, id: \.name) { preset in
                            presetSwatch(preset)
                        }
                    }
                }

                section("Colors") {
                    VStack(alignment: .leading, spacing: 8) {
                        picker("Card top", \.cardTop)
                        picker("Card bottom", \.cardBottom)
                        picker("Record", \.vinyl)
                        picker("Panel", \.panel)
                        picker("Buttons", \.knob)
                        picker("Accent", \.accent)
                        picker("Text", \.text)
                        picker("Tonearm", \.arm)
                    }
                }

                section("Size") {
                    HStack(spacing: 12) {
                        Slider(value: $settings.scale, in: 0.7...1.6, step: 0.05)
                        Text("\(Int(settings.scale * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                section("Behavior") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Sit on the wallpaper (behind all windows)",
                               isOn: $settings.pinnedToDesktop)
                        Text("Off = floats above your windows. Show your desktop to see it when on.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)

                        Toggle("Spin the record while playing", isOn: $settings.spinRecord)
                        Toggle("Show the tonearm", isOn: $settings.showTonearm)
                        Toggle("Show the control panel", isOn: $settings.showPanel)
                            .disabled(settings.compactMode)
                        Toggle("Compact mode (controls only)", isOn: $settings.compactMode)

                        Toggle("Open at login", isOn: Binding(
                            get: { loginAtStart },
                            set: { want in
                                do { try LoginItem.set(want); loginAtStart = want; loginError = nil }
                                catch {
                                    loginError = "Couldn’t change this: \(error.localizedDescription)"
                                    loginAtStart = LoginItem.isEnabled
                                }
                            }))
                        if let loginError {
                            Text(loginError)
                                .font(.system(size: 10))
                                .foregroundStyle(.red)
                                .padding(.leading, 20)
                        }
                    }
                    .toggleStyle(.checkbox)
                }

                HStack(spacing: 10) {
                    Button("Reset Position") { onResetPosition() }
                    Button("Reset Theme") { settings.resetToDefaults() }
                    Spacer()
                    Button("Quit Widget") { NSApp.terminate(nil) }
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(width: 420)
        .frame(maxHeight: .infinity)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func picker(_ label: String, _ keyPath: WritableKeyPath<Theme, String>) -> some View {
        HStack {
            Text(label).font(.system(size: 12))
            Spacer()
            ColorPicker("", selection: Binding(
                get: { Color(hex: settings.theme[keyPath: keyPath]) },
                set: { newValue in
                    settings.theme[keyPath: keyPath] = newValue.hexString
                    if Theme.presets.contains(where: { $0.name == settings.theme.name }) {
                        settings.theme.name = "Custom"
                    }
                }), supportsOpacity: false)
                .labelsHidden()
        }
    }

    private func presetSwatch(_ preset: Theme) -> some View {
        let selected = settings.theme == preset
        return Button {
            settings.theme = preset
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [preset.cardTopColor, preset.cardBottomColor],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle().fill(preset.vinylColor).frame(width: 30, height: 30)
                    Circle().fill(preset.accentColor).frame(width: 11, height: 11)
                }
                .frame(height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.15),
                                      lineWidth: selected ? 2.5 : 1)
                )
                Text(preset.name).font(.system(size: 10))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
