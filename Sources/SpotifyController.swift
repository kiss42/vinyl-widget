import AppKit
import Foundation

struct TrackState: Equatable {
    var running = false
    var playing = false
    var title = ""
    var artist = ""
    var album = ""
    var trackID = ""
    var artworkURL = ""
    var duration: Double = 0   // seconds
    var position: Double = 0   // seconds
    var volume: Double = 50    // 0...100
    var shuffling = false
    var repeating = false
}

/// Talks to the Spotify desktop app over Apple Events (osascript run off the main thread).
/// No Spotify account / API key involved.
@MainActor
final class SpotifyController: ObservableObject {
    @Published private(set) var state = TrackState()
    @Published private(set) var artwork: NSImage?
    /// True when Spotify is running but Apple Events are being refused (missing Automation permission).
    @Published private(set) var controlBlocked = false
    /// False when the Spotify app can't be found on this Mac at all.
    @Published private(set) var spotifyInstalled = true

    /// Set while the user drags the progress bar so polling doesn't fight the drag.
    var scrubbing = false

    private var timer: Timer?
    private var lastSync = Date.distantPast
    private var loadedArtworkFor = ""
    private let shell = DispatchQueue(label: "spotify.widget.osascript", qos: .userInitiated)

    private let readScript = """
    tell application "Spotify"
        set playState to (player state as text)
        set playPos to player position
        set soundVol to sound volume
        try
            set isShuffling to (shuffling as text)
        on error
            set isShuffling to "false"
        end try
        try
            set isRepeating to (repeating as text)
        on error
            set isRepeating to "false"
        end try
        set trackName to ""
        set trackArtist to ""
        set trackAlbum to ""
        set trackDuration to 0
        set trackArtwork to ""
        set trackIdent to ""
        try
            set theTrack to current track
            set trackName to name of theTrack
            set trackArtist to artist of theTrack
            set trackAlbum to album of theTrack
            set trackDuration to duration of theTrack
            set trackArtwork to artwork url of theTrack
            set trackIdent to id of theTrack
        end try
        return playState & tab & playPos & tab & soundVol & tab & isShuffling & tab & isRepeating & tab & trackDuration & tab & trackIdent & tab & trackName & tab & trackArtist & tab & trackAlbum & tab & trackArtwork
    end tell
    """

    init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.tick() }
        }
        refresh()
    }

    // MARK: - Polling

    private static let spotifyBundleID = "com.spotify.client"

    private var spotifyIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.spotifyBundleID).isEmpty
    }

    /// Wherever the user actually keeps Spotify — not necessarily /Applications.
    private var spotifyURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.spotifyBundleID)
    }

    /// Advance the clock locally between syncs so the bar moves smoothly, and re-sync periodically.
    private func tick() {
        if state.playing && !scrubbing {
            state.position = min(state.position + 0.5, max(state.duration, 0))
        }
        if Date().timeIntervalSince(lastSync) > 3 { refresh() }
    }

    func refresh() {
        spotifyInstalled = spotifyURL != nil
        guard spotifyIsRunning else {
            if state.running { state = TrackState() }
            artwork = nil
            loadedArtworkFor = ""
            lastSync = Date()
            return
        }
        lastSync = Date()
        let script = readScript
        shell.async { [weak self] in
            let out = Self.runOsascript(script)
            guard let self else { return }
            guard let out else {
                DispatchQueue.main.async { self.controlBlocked = true }
                return
            }
            let f = out.components(separatedBy: "\t")
            guard f.count >= 11 else { return }
            var s = TrackState()
            s.running = true
            s.playing = f[0].trimmingCharacters(in: .whitespaces) == "playing"
            s.position = Double(f[1]) ?? 0
            s.volume = Double(f[2]) ?? 50
            s.shuffling = f[3] == "true"
            s.repeating = f[4] == "true"
            let rawDuration = Double(f[5]) ?? 0
            // Spotify reports track duration in milliseconds; older builds used seconds.
            s.duration = rawDuration > 10_000 ? rawDuration / 1000 : rawDuration
            s.trackID = f[6]
            s.title = f[7]
            s.artist = f[8]
            s.album = f[9]
            s.artworkURL = f[10].trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.controlBlocked = false
                self.apply(s)
            }
        }
    }

    private func apply(_ s: TrackState) {
        var s = s
        if scrubbing { s.position = state.position }
        state = s
        loadArtworkIfNeeded()
    }

    private func loadArtworkIfNeeded() {
        let key = state.trackID.isEmpty ? state.artworkURL : state.trackID
        guard !key.isEmpty, key != loadedArtworkFor,
              let url = URL(string: state.artworkURL) else { return }
        loadedArtworkFor = key
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let img = NSImage(data: data) else { return }
            DispatchQueue.main.async { self?.artwork = img }
        }.resume()
    }

    // MARK: - Commands

    func playPause() { send("playpause"); optimisticToggle() }
    func next() { send("next track"); bump() }
    func previous() { send("previous track"); bump() }
    func toggleShuffle() {
        state.shuffling.toggle()
        send("set shuffling to \(state.shuffling)")
    }
    func toggleRepeat() {
        state.repeating.toggle()
        send("set repeating to \(state.repeating)")
    }
    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, state.duration))
        state.position = clamped
        send("set player position to \(clamped)")
    }
    func setVolume(_ v: Double) {
        state.volume = v
        send("set sound volume to \(Int(v.rounded()))")
    }
    func openAutomationSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!
        NSWorkspace.shared.open(url)
    }

    func activateSpotify() {
        guard let url = spotifyURL else { openSpotifyDownloadPage(); return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openSpotifyDownloadPage() {
        guard let url = URL(string: "https://www.spotify.com/download/mac/") else { return }
        NSWorkspace.shared.open(url)
    }

    private func optimisticToggle() {
        state.playing.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.refresh() }
    }

    private func bump() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.refresh() }
    }

    private func send(_ command: String) {
        let script = "tell application \"Spotify\" to \(command)"
        shell.async { _ = Self.runOsascript(script) }
    }

    private nonisolated static func runOsascript(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines)
    }
}
