//
//  Preferences.swift
//  MacNotchPlayer
//
//  Small UserDefaults-backed settings store, shared between the Settings window
//  and the runtime logic (NotchController).
//

import AppKit
import SwiftUI

/// What the customizable indicator on the *trailing* (right) side of the notch shows.
enum TrailingIndicator: String, CaseIterable, Identifiable {
    case equalizer        // animated bars while music plays (default)
    case macBattery       // this Mac's battery, as a ring
    case headphonesBattery // connected AirPods / Bluetooth headphones, as a ring

    var id: String { rawValue }
}

/// Strength of the haptic tap when the notch is hovered. macOS has no raw
/// amplitude control, so strength is a burst of quick taps using the strongest
/// system pattern (`.levelChange`).
enum HapticStrength: String, CaseIterable, Identifiable {
    case light
    case medium
    case strong

    var id: String { rawValue }

    /// Plays the feedback. `performanceTime: .now` is required: `.default` can
    /// be silently dropped when there is no accompanying draw event.
    /// Light and medium are a single tap of increasing intensity; strong is a
    /// double tap.
    @MainActor
    func play() {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch self {
        case .light:
            performer.perform(.generic, performanceTime: .now)
        case .medium:
            performer.perform(.levelChange, performanceTime: .now)
        case .strong:
            performer.perform(.levelChange, performanceTime: .now)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    /// Show an album-art thumbnail + animated equalizer beside the notch while playing.
    @Published var showCompactIndicator: Bool {
        didSet { defaults.set(showCompactIndicator, forKey: "showCompactIndicator") }
    }
    /// Briefly slide the player out when the track changes.
    @Published var autoPeekOnTrackChange: Bool {
        didSet { defaults.set(autoPeekOnTrackChange, forKey: "autoPeekOnTrackChange") }
    }
    /// Briefly slide the player out when playback is paused or resumed.
    @Published var autoPeekOnPlayPause: Bool {
        didSet { defaults.set(autoPeekOnPlayPause, forKey: "autoPeekOnPlayPause") }
    }
    /// Hide the notch player while another app is in fullscreen (e.g. watching a film).
    @Published var hideInFullscreen: Bool {
        didSet { defaults.set(hideInFullscreen, forKey: "hideInFullscreen") }
    }
    /// What the indicator on the right side of the notch shows.
    @Published var trailingIndicator: TrailingIndicator {
        didSet { defaults.set(trailingIndicator.rawValue, forKey: "trailingIndicator") }
    }
    /// Color the transport buttons with a color sampled from the album artwork.
    @Published var colorButtons: Bool {
        didSet { defaults.set(colorButtons, forKey: "colorButtons") }
    }
    /// UI language.
    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language") }
    }
    /// Subtle haptic feedback when the notch is hovered.
    @Published var hapticOnHover: Bool {
        didSet { defaults.set(hapticOnHover, forKey: "hapticOnHover") }
    }
    /// How strong the hover haptic feels.
    @Published var hapticStrength: HapticStrength {
        didSet { defaults.set(hapticStrength.rawValue, forKey: "hapticStrength") }
    }
    /// How long the auto-peek stays open, in seconds.
    @Published var peekDuration: Double {
        didSet { defaults.set(peekDuration, forKey: "peekDuration") }
    }

    private init() {
        let d = UserDefaults.standard
        func boolOr(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key) == nil ? fallback : d.bool(forKey: key)
        }
        showCompactIndicator = boolOr("showCompactIndicator", true)
        autoPeekOnTrackChange = boolOr("autoPeekOnTrackChange", true)
        autoPeekOnPlayPause = boolOr("autoPeekOnPlayPause", true)
        hideInFullscreen = boolOr("hideInFullscreen", true)
        trailingIndicator = TrailingIndicator(rawValue: d.string(forKey: "trailingIndicator") ?? "") ?? .equalizer
        colorButtons = boolOr("colorButtons", true)
        hapticOnHover = boolOr("hapticOnHover", false)
        hapticStrength = HapticStrength(rawValue: d.string(forKey: "hapticStrength") ?? "") ?? .medium
        peekDuration = (d.object(forKey: "peekDuration") as? Double) ?? 3.0
        language = AppLanguage(rawValue: d.string(forKey: "language") ?? "") ?? .systemDefault()
    }

    func t(_ key: L) -> String { key.string(language) }
}
