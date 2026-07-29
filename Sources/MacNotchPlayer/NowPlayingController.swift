//
//  NowPlayingController.swift
//  MacNotchPlayer
//
//  Bridges the bundled `mediaremote-adapter` Perl tool to SwiftUI:
//   - launches `perl … stream` and parses live now-playing updates,
//   - interpolates the elapsed time so the scrubber moves smoothly,
//   - sends playback commands (toggle / next / previous / seek).
//
//  This is the only path that works on macOS 15.4+ / 26, where the private
//  MediaRemote framework is otherwise locked down for un-entitled apps.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class NowPlayingController: ObservableObject {
    // Published UI state.
    @Published private(set) var current = NowPlaying()
    @Published private(set) var artwork: NSImage?
    /// Accent color sampled from the artwork (or a fallback).
    @Published private(set) var accent: Color = .purple
    /// Elapsed time in seconds, interpolated between adapter updates.
    @Published var displayedElapsed: Double = 0
    /// System output volume, 0...1.
    @Published var volume: Double = 0.5

    /// While the user drags the scrubber we stop interpolating.
    var isScrubbing = false
    /// While the user drags the volume slider we stop polling it.
    var isAdjustingVolume = false

    /// Fires when the playing track changes (used for auto-peek).
    let trackChanged = PassthroughSubject<Void, Never>()
    /// Fires when playback is paused or resumed (used for auto-peek).
    let playbackToggled = PassthroughSubject<Void, Never>()

    private var tickCount = 0

    // Interpolation anchors.
    private var baseElapsed: Double = 0
    private var baseDate = Date()
    private var ticker: Timer?

    // Stream process + parsing state (parsing runs on the readability thread,
    // which Foundation invokes serially, so these are safe to mutate there).
    private var streamProcess: Process?
    nonisolated(unsafe) private var lineBuffer = Data()
    nonisolated(unsafe) private var raw: [String: Any] = [:]
    nonisolated(unsafe) private var lastArtworkBase64: String?

    // MARK: - Lifecycle

    func start() {
        guard AdapterPaths.isAvailable else {
            NSLog("MacNotchPlayer: mediaremote-adapter resources not found.")
            return
        }
        startTicker()
        startStream()
        refreshVolume()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        streamProcess?.terminate()
        streamProcess = nil
    }

    // MARK: - Streaming

    private func startStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AdapterPaths.perl)
        process.arguments = [
            AdapterPaths.scriptPath,
            AdapterPaths.frameworkPath,
            "stream",
            "--debounce=150"
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe() // swallow non-fatal stderr noise

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.consume(data)
        }

        process.terminationHandler = { [weak self] _ in
            // If the adapter dies, retry once after a short delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let self, self.streamProcess != nil else { return }
                self.streamProcess = nil
                self.startStream()
            }
        }

        do {
            try process.run()
            streamProcess = process
        } catch {
            NSLog("MacNotchPlayer: failed to launch adapter stream: \(error)")
        }
    }

    /// Runs on the readability thread. Splits the byte stream into lines.
    nonisolated private func consume(_ data: Data) {
        lineBuffer.append(data)
        let newline = UInt8(0x0A)
        while let idx = lineBuffer.firstIndex(of: newline) {
            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<idx)
            lineBuffer.removeSubrange(lineBuffer.startIndex...idx)
            guard !lineData.isEmpty else { continue }
            handleLine(lineData)
        }
    }

    nonisolated private func handleLine(_ lineData: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: lineData),
            let dict = object as? [String: Any],
            (dict["type"] as? String) == "data",
            let payload = dict["payload"] as? [String: Any]
        else { return }

        let diff = (dict["diff"] as? Bool) ?? false
        NowPlayingParser.merge(payload, into: &raw, diff: diff)
        let np = NowPlayingParser.makeNowPlaying(from: raw)

        // Decode artwork + sample accent only when it actually changed (off main).
        var newArtwork: NSImage??  // nil = unchanged, .some(nil) = cleared
        var newAccent: Color?
        if np.artworkBase64 != lastArtworkBase64 {
            lastArtworkBase64 = np.artworkBase64
            if let b64 = np.artworkBase64,
               let imgData = Data(base64Encoded: b64),
               let image = NSImage(data: imgData) {
                newArtwork = .some(image)
                newAccent = ArtworkColor.accent(from: image)
            } else {
                newArtwork = .some(nil)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.apply(np, artwork: newArtwork, accent: newAccent)
        }
    }

    private func apply(_ np: NowPlaying, artwork newArtwork: NSImage??, accent newAccent: Color?) {
        let didChangeTrack = np.hasMedia && np.trackKey != current.trackKey
        // Play/pause toggles without a track change (don't double-fire when the
        // track itself changed — that already triggers its own peek).
        let didTogglePlayback = np.hasMedia && !didChangeTrack
            && current.hasMedia && np.playing != current.playing
        current = np
        baseElapsed = np.elapsedTime
        baseDate = Date()
        if !isScrubbing {
            displayedElapsed = np.elapsedTime
        }
        if let newArtwork {
            artwork = newArtwork
        }
        if let newAccent {
            accent = newAccent
        }
        if didChangeTrack {
            trackChanged.send()
        }
        if didTogglePlayback {
            playbackToggled.send()
        }
    }

    // MARK: - Smooth elapsed-time interpolation

    private func startTicker() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        // Poll system volume every ~1.5s (unless the user is dragging it).
        tickCount += 1
        if tickCount % 3 == 0, !isAdjustingVolume {
            refreshVolume()
        }
        guard !isScrubbing, current.playing, current.duration > 0 else { return }
        let elapsed = baseElapsed + Date().timeIntervalSince(baseDate)
        displayedElapsed = min(current.duration, max(0, elapsed))
    }

    // MARK: - Playback commands

    func togglePlayPause() { send("send", "2") }
    func nextTrack() { send("send", "4") }
    func previousTrack() { send("send", "5") }

    /// Toggle shuffle between off (1) and shuffle-tracks (3).
    func toggleShuffle() {
        let next = current.shuffleOn ? 1 : 3
        current.shuffleMode = next
        send("shuffle", String(next))
    }

    /// Cycle repeat: off (1) → track (2) → playlist (3) → off.
    func cycleRepeat() {
        let next = ((current.repeatMode ?? 1) % 3) + 1
        current.repeatMode = next
        send("repeat", String(next))
    }

    func seek(toSeconds seconds: Double) {
        let micros = Int((max(0, seconds) * 1_000_000).rounded())
        send("seek", String(micros))
        // Optimistically reflect the new position.
        baseElapsed = seconds
        baseDate = Date()
        displayedElapsed = seconds
    }

    // MARK: - System volume (via osascript)

    func refreshVolume() {
        Shell.runAsync("/usr/bin/osascript", ["-e", "output volume of (get volume settings)"]) { [weak self] out in
            guard let value = Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            Task { @MainActor in
                guard let self, !self.isAdjustingVolume else { return }
                self.volume = value / 100.0
            }
        }
    }

    private var volumeApplyScheduled = false
    private var pendingVolume: Double?

    /// Called continuously while dragging: update immediately, throttle the
    /// (relatively slow) osascript call so the slider stays responsive.
    func setVolumeLive(_ newValue: Double) {
        volume = newValue
        pendingVolume = newValue
        guard !volumeApplyScheduled else { return }
        volumeApplyScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.volumeApplyScheduled = false
            if let pending = self.pendingVolume {
                self.applyVolume(pending)
                self.pendingVolume = nil
            }
        }
    }

    /// Called on drag end (or discrete set): apply the final value.
    func setVolume(_ newValue: Double) {
        volume = newValue
        applyVolume(newValue)
    }

    private func applyVolume(_ value: Double) {
        let pct = Int((max(0, min(1, value)) * 100).rounded())
        Shell.runAsync("/usr/bin/osascript", ["-e", "set volume output volume \(pct)"], completion: { _ in })
    }

    private func send(_ command: String, _ argument: String) {
        guard AdapterPaths.isAvailable else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AdapterPaths.perl)
        process.arguments = [AdapterPaths.scriptPath, AdapterPaths.frameworkPath, command, argument]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}

/// Fire-and-forget shell command runner that captures stdout off the main thread.
enum Shell {
    static func runAsync(_ launchPath: String, _ arguments: [String], completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: launchPath)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                completion(String(data: data, encoding: .utf8) ?? "")
            } catch {
                completion("")
            }
        }
    }
}

/// Resolves the absolute paths of the bundled adapter resources.
enum AdapterPaths {
    static let perl = "/usr/bin/perl"

    static var scriptPath: String { resource(named: "mediaremote-adapter", ext: "pl") ?? "" }

    static var frameworkPath: String {
        if let base = Bundle.main.resourceURL {
            let url = base.appendingPathComponent("MediaRemoteAdapter.framework")
            if FileManager.default.fileExists(atPath: url.path) { return url.path }
        }
        // Dev fallback: alongside the executable.
        return devResourcesDir().appendingPathComponent("MediaRemoteAdapter.framework").path
    }

    static var isAvailable: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: scriptPath)
            && fm.fileExists(atPath: frameworkPath)
            && fm.fileExists(atPath: perl)
    }

    private static func resource(named name: String, ext: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url.path
        }
        let candidate = devResourcesDir().appendingPathComponent("\(name).\(ext)")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate.path : nil
    }

    /// `MACNOTCH_RESOURCES` override or the project's `Resources` dir, for `swift run`.
    private static func devResourcesDir() -> URL {
        if let override = ProcessInfo.processInfo.environment["MACNOTCH_RESOURCES"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MacNotchPlayer
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Resources")
    }
}
