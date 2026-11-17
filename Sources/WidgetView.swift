import SwiftUI
import AppKit

// MARK: - Base metrics (scaled at draw time)

let baseCardW: CGFloat = 280
let basePlatterH: CGFloat = 280
let baseGap: CGFloat = 10
let basePanelH: CGFloat = 122
let baseTotalH: CGFloat = basePlatterH + baseGap + basePanelH   // 412

private let recordCenter = CGPoint(x: 140, y: 150)
private let recordRadius: CGFloat = 99
private let labelRadius: CGFloat = 45
private let armPivot = CGPoint(x: 238, y: 62)

func timeString(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let s = Int(seconds.rounded())
    return String(format: "%d:%02d", s / 60, s % 60)
}

private extension Double {
    var clamped01: Double { Swift.min(Swift.max(self, 0), 1) }
}

// AppKit keeps the mouse-down view for the entire drag, even while the widget's
// window changes size. Screen coordinates don't move as the window is resized.
private struct ResizeHandleInput: NSViewRepresentable {
    var scale: Double
    var baseHeight: CGFloat
    var onResize: (Double) -> Void

    func makeNSView(context: Context) -> ResizeHandleView { ResizeHandleView() }

    func updateNSView(_ view: ResizeHandleView, context: Context) {
        view.scale = scale
        view.baseHeight = baseHeight
        view.onResize = onResize
    }
}

private final class ResizeHandleView: NSView {
    var scale: Double = 1
    var baseHeight: CGFloat = basePanelH
    var onResize: (Double) -> Void = { _ in }
    private var startPoint = NSPoint.zero
    private var startScale: Double = 1
    private var startHeight: CGFloat = basePanelH

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var resizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(position: .bottomRight, directions: .all)
        }
        return .resizeLeftRight
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: resizeCursor)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = NSEvent.mouseLocation
        startScale = scale
        startHeight = baseHeight
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = point.x - startPoint.x
        let dy = startPoint.y - point.y
        // Project onto the widget's aspect-ratio diagonal, in screen points.
        let delta = (dx * baseCardW + dy * startHeight)
            / (baseCardW * baseCardW + startHeight * startHeight)
        onResize(min(1.6, max(0.7, startScale + delta)))
    }
}

// MARK: - Draggable bar

private struct Bar: View {
    var progress: Double
    var height: CGFloat
    var tint: Color
    var onChange: (Double) -> Void
    var onCommit: (Double) -> Void
    @State private var hovering = false
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let emphasized = hovering || dragging
            let barHeight = emphasized ? min(height + 2, geo.size.height) : height
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(emphasized ? 0.28 : 0.16)).frame(height: barHeight)
                Capsule().fill(tint).frame(width: w * progress.clamped01, height: barHeight)
                if emphasized {
                    Circle().fill(tint)
                        .frame(width: 8, height: 8)
                        .position(x: min(max(w * progress.clamped01, 4), max(w - 4, 4)),
                                  y: geo.size.height / 2)
                }
            }
            .frame(width: w, height: geo.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragging = true; onChange(($0.location.x / w).clamped01) }
                    .onEnded { onCommit(($0.location.x / w).clamped01); dragging = false }
            )
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: emphasized)
        }
    }
}

// MARK: - Scaling wrapper

struct WidgetRoot: View {
    @ObservedObject var settings: Settings
    @ObservedObject var spotify: SpotifyController
    var interactive: Bool = true
    var onSettings: () -> Void = {}

    private var baseH: CGFloat { settings.baseHeight }

    var body: some View {
        WidgetView(settings: settings, spotify: spotify,
                   interactive: interactive, onSettings: onSettings)
            .frame(width: baseCardW, height: baseH)
            .scaleEffect(settings.scale)
            .frame(width: baseCardW * settings.scale, height: baseH * settings.scale)
    }
}

// MARK: - Widget

struct WidgetView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var spotify: SpotifyController
    var interactive: Bool = true
    var onSettings: () -> Void = {}

    @State private var hovering = false
    @State private var dragProgress: Double? = nil
    @State private var spin: Double = 0
    @State private var spinStartedAt: TimeInterval?

    private var theme: Theme { settings.theme }

    var body: some View {
        VStack(spacing: baseGap) {
            if !settings.compactMode { platter }
            if settings.showPanel || settings.compactMode { panel }
        }
        .frame(width: baseCardW, height: settings.baseHeight)
        .overlay(alignment: .bottomTrailing) {
            if interactive { resizeHandle }
        }
        .onHover { h in
            guard interactive else { return }
            withAnimation(.easeOut(duration: 0.15)) { hovering = h }
        }
        .onAppear { updateSpinState() }
        .onChange(of: spotify.state.playing) { _ in updateSpinState() }
        .onChange(of: settings.spinRecord) { _ in updateSpinState() }
        .allowsHitTesting(interactive)
        .contextMenu {
            Button("Customize…") { onSettings() }
            Button(settings.compactMode ? "Show Turntable" : "Compact Mode") {
                settings.compactMode.toggle()
            }
            Button("Open Spotify") { spotify.activateSpotify() }
            Divider()
            Button("Quit Vinyl Widget") { NSApp.terminate(nil) }
        }
    }

    private func updateSpinState() {
        let now = ProcessInfo.processInfo.systemUptime
        if let started = spinStartedAt {
            spin = (spin + (now - started) * 200).truncatingRemainder(dividingBy: 360)
        }
        spinStartedAt = spotify.state.playing && settings.spinRecord ? now : nil
    }

    private var spinAngle: Double {
        guard let started = spinStartedAt else { return spin }
        return (spin + (ProcessInfo.processInfo.systemUptime - started) * 200)
            .truncatingRemainder(dividingBy: 360)
    }

    private var progress: Double {
        if let d = dragProgress { return d }
        guard spotify.state.duration > 0 else { return 0 }
        return (spotify.state.position / spotify.state.duration).clamped01
    }

    private var resizeHandle: some View {
        ZStack {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(theme.textColor.opacity(0.7))
                .allowsHitTesting(false)
            ResizeHandleInput(scale: settings.scale, baseHeight: settings.baseHeight) {
                settings.scale = $0
            }
        }
            .frame(width: 20, height: 20)
            .padding([.bottom, .trailing], 6)
            .accessibilityLabel("Drag to resize widget")
            .help("Drag to resize")
    }

    // MARK: Turntable

    private var platter: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(LinearGradient(colors: [theme.cardTopColor, theme.cardBottomColor],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
            vinyl.position(recordCenter)

            if settings.showTonearm { tonearm }

        }
        .frame(width: baseCardW, height: basePlatterH)
        .overlay(alignment: .topLeading) {
            if hovering { gearButton.padding(9) }
        }
    }

    private var vinyl: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [theme.vinylColor.opacity(0.92), theme.vinylColor],
                                     center: .center, startRadius: 10, endRadius: recordRadius))
                .frame(width: recordRadius * 2, height: recordRadius * 2)
                .shadow(color: .black.opacity(0.55), radius: 10, y: 4)

            ForEach(0..<9, id: \.self) { i in
                let r = labelRadius + 6 + CGFloat(i) * 6
                Circle()
                    .strokeBorder(Color.white.opacity(0.045), lineWidth: 1)
                    .frame(width: r * 2, height: r * 2)
            }

            Circle()
                .fill(AngularGradient(colors: [.white.opacity(0.0), .white.opacity(0.10),
                                               .white.opacity(0.0), .white.opacity(0.06),
                                               .white.opacity(0.0)],
                                      center: .center))
                .frame(width: recordRadius * 2, height: recordRadius * 2)
                .blendMode(.plusLighter)

            TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                    paused: !spotify.state.playing || !settings.spinRecord)) { _ in
                Group {
                    if let art = spotify.artwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Circle().fill(theme.knobColor)
                            Image(systemName: "music.note")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(theme.textColor.opacity(0.55))
                        }
                    }
                }
                .frame(width: labelRadius * 2, height: labelRadius * 2)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                // The light and record shadow stay still; only the label rotates.
                // Negate for NSHostingView's y-up coordinate space.
                .rotationEffect(.degrees(-spinAngle))
            }
            .frame(width: labelRadius * 2, height: labelRadius * 2)

            Circle().fill(theme.armColor.opacity(0.8)).frame(width: 7, height: 7)
            Circle().fill(Color.black.opacity(0.85)).frame(width: 4, height: 4)
        }
        .frame(width: recordRadius * 2, height: recordRadius * 2)
        .onTapGesture { spotify.playPause() }
    }

    /// Screen-space angle: 0 points straight down, negative swings the arm left onto
    /// the record. While playing the stylus tracks inward as the song progresses.
    private var armAngle: Double {
        spotify.state.playing ? (-12 - progress * 14) : 10
    }

    private var tonearm: some View {
        let pivotD: CGFloat = 34
        let armLen: CGFloat = 104
        let headLen: CGFloat = 22
        let stackH = pivotD + armLen + headLen

        return VStack(spacing: 0) {
            ZStack {
                Circle().fill(LinearGradient(colors: [theme.armColor,
                                                      theme.armColor.opacity(0.65)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
                Circle().fill(Color.black.opacity(0.35)).frame(width: 9, height: 9)
            }
            .frame(width: pivotD, height: pivotD)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)

            Capsule()
                .fill(LinearGradient(colors: [theme.armColor, theme.armColor.opacity(0.7)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 5, height: armLen)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [theme.armColor.opacity(0.9),
                                              theme.armColor.opacity(0.55)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 13, height: headLen)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .frame(width: pivotD, height: stackH)
        .rotationEffect(.degrees(-armAngle), anchor: UnitPoint(x: 0.5, y: (pivotD / 2) / stackH))
        .position(x: armPivot.x, y: armPivot.y - pivotD / 2 + stackH / 2)
        .animation(.easeInOut(duration: 0.7), value: spotify.state.playing)
    }

    // MARK: Control panel

    private var headline: String {
        if !spotify.spotifyInstalled { return "Spotify isn’t installed" }
        if spotify.controlBlocked { return "Allow Spotify control" }
        if !spotify.state.running { return "Spotify isn’t running" }
        return spotify.state.title.isEmpty ? "—" : spotify.state.title
    }

    private var subhead: String {
        if !spotify.spotifyInstalled { return "click to download it" }
        if spotify.controlBlocked { return "click to open Settings" }
        if !spotify.state.running { return "click to open Spotify" }
        return spotify.state.artist
    }

    private func headlineTapped() {
        if !spotify.spotifyInstalled { spotify.openSpotifyDownloadPage() }
        else if spotify.controlBlocked { spotify.openAutomationSettings() }
        else if !spotify.state.running { spotify.activateSpotify() }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(headline)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.textColor)
                .lineLimit(1).truncationMode(.tail)
                .frame(width: baseCardW - 64, height: 19, alignment: .leading)

            Text(subhead)
                .font(.system(size: 11))
                .foregroundStyle(theme.textColor.opacity(0.55))
                .lineLimit(1).truncationMode(.tail)
                .frame(width: baseCardW - 36, height: 15, alignment: .leading)

            Spacer(minLength: 0).frame(height: 7)

            Bar(progress: progress, height: 3, tint: theme.accentColor,
                onChange: { p in spotify.scrubbing = true; dragProgress = p },
                onCommit: { p in
                    spotify.seek(to: p * spotify.state.duration)
                    dragProgress = nil
                    spotify.scrubbing = false
                })
                .frame(width: baseCardW - 36, height: 8)

            Spacer(minLength: 0).frame(height: 5)

            buttonRow.frame(width: baseCardW - 36, height: 40)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: baseCardW, height: basePanelH, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(theme.panelColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { settings.compactMode.toggle() } label: {
                    Image(systemName: settings.compactMode ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.textColor.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(theme.knobColor.opacity(0.8)))
                }
                .buttonStyle(KnobButtonStyle())
                .help(settings.compactMode ? "Show turntable" : "Compact mode")
                .padding(.top, 9)
                .padding(.trailing, 10)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { headlineTapped() }
    }

    private var buttonRow: some View {
        HStack(spacing: 0) {
            knob("backward.end.fill", 12) { spotify.previous() }
            Spacer(minLength: 0)
            knob(spotify.state.playing ? "pause.fill" : "play.fill", 13, big: true) { spotify.playPause() }
            Spacer(minLength: 0)
            knob("forward.end.fill", 12) { spotify.next() }
            Spacer(minLength: 0)
            knob("shuffle", 11, active: spotify.state.shuffling) { spotify.toggleShuffle() }
        }
    }

    private func knob(_ symbol: String, _ size: CGFloat, big: Bool = false, active: Bool = false,
                      action: @escaping () -> Void) -> some View {
        let d: CGFloat = big ? 40 : 36
        return Button(action: action) {
            ZStack {
                Circle().fill(LinearGradient(colors: [theme.knobColor,
                                                      theme.knobColor.opacity(0.55)],
                                             startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.03)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
                Image(systemName: symbol)
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(active ? theme.accentColor : theme.textColor.opacity(0.9))
            }
            .frame(width: d, height: d)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            .contentShape(Circle())
        }
        .buttonStyle(KnobButtonStyle())
    }

    private var gearButton: some View {
        Button(action: onSettings) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.9))
                .frame(width: 19, height: 19)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .buttonStyle(KnobButtonStyle())
        .help("Customize the widget")
    }
}

private struct KnobButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.26 : (hovering ? 0.14 : 0))))
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}
