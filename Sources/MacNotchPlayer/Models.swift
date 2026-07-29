//
//  Models.swift
//  MacNotchPlayer
//
//  The now-playing state shown in the notch, plus helpers to build it from the
//  JSON payload emitted by mediaremote-adapter.
//

import AppKit

/// A snapshot of the system "now playing" state.
struct NowPlaying: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var bundleIdentifier: String?
    var playing: Bool = false

    /// Total track length in seconds (0 when unknown).
    var duration: Double = 0
    /// Elapsed playback time in seconds, as reported at `receivedAt`.
    var elapsedTime: Double = 0

    /// Raw base64 string of the artwork, kept to detect when artwork changes.
    var artworkBase64: String?

    /// MediaRemote shuffle mode: 1 = off, 2 = albums, 3 = tracks.
    var shuffleMode: Int?
    /// MediaRemote repeat mode: 1 = off, 2 = track, 3 = playlist.
    var repeatMode: Int?
    /// Whether the source is a dedicated music app (vs. a browser tab, etc.).
    var isMusicApp: Bool = false

    var hasMedia: Bool { title?.isEmpty == false }

    var shuffleOn: Bool { (shuffleMode ?? 1) >= 2 }
    var repeatOn: Bool { (repeatMode ?? 1) >= 2 }

    /// A short key identifying the current track, for change detection.
    var trackKey: String { "\(bundleIdentifier ?? "")|\(title ?? "")|\(album ?? "")|\(artist ?? "")" }

    /// A short "Artist — Title" string for the menu bar.
    var menuLabel: String {
        guard hasMedia else { return "Нічого не грає" }
        if let artist, !artist.isEmpty {
            return "\(artist) — \(title ?? "")"
        }
        return title ?? "—"
    }
}

enum NowPlayingParser {
    /// Merges a stream `payload` dictionary into the accumulated raw state.
    ///
    /// When `diff` is true only changed keys are present; a key mapped to
    /// `NSNull` means it vanished and must be removed.
    static func merge(_ payload: [String: Any], into raw: inout [String: Any], diff: Bool) {
        if !diff {
            raw = [:]
        }
        for (key, value) in payload {
            if value is NSNull {
                raw.removeValue(forKey: key)
            } else {
                raw[key] = value
            }
        }
    }

    /// Builds a typed `NowPlaying` from the accumulated raw dictionary.
    static func makeNowPlaying(from raw: [String: Any]) -> NowPlaying {
        var np = NowPlaying()
        np.title = raw["title"] as? String
        np.artist = raw["artist"] as? String
        np.album = raw["album"] as? String
        np.bundleIdentifier = raw["bundleIdentifier"] as? String
        np.playing = (raw["playing"] as? Bool) ?? false
        np.duration = (raw["duration"] as? NSNumber)?.doubleValue ?? 0
        np.elapsedTime = (raw["elapsedTime"] as? NSNumber)?.doubleValue ?? 0
        np.artworkBase64 = raw["artworkData"] as? String
        np.shuffleMode = (raw["shuffleMode"] as? NSNumber)?.intValue
        np.repeatMode = (raw["repeatMode"] as? NSNumber)?.intValue
        np.isMusicApp = (raw["isMusicApp"] as? Bool) ?? false
        return np
    }
}

/// Formats a number of seconds as `m:ss` (or `h:mm:ss`).
func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}
