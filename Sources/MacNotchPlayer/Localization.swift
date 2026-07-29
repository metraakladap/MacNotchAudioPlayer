//
//  Localization.swift
//  MacNotchPlayer
//
//  Lightweight in-app localization (English / Ukrainian) driven by a user
//  preference rather than .lproj bundles, so the language can be switched live.
//

import AppKit
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english
    case ukrainian

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .ukrainian: return "Українська"
        }
    }

    static func systemDefault() -> AppLanguage {
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("uk") ? .ukrainian : .english
    }
}

enum L: String {
    case nothingPlaying
    case play, pause, next, previous, settings, quit
    case openApp
    case sectionAppearance, showCompact, colorButtons, haptic
    case hapticStrength, hapticLight, hapticMedium, hapticStrong
    case trailingIndicator, trailingEqualizer, trailingMacBattery, trailingHeadphones, trailingNote
    case sectionPeek, autoPeek, autoPeekPlayPause, duration, secondsSuffix
    case hideInFullscreen, hideInFullscreenNote
    case sectionSystem, launchAtLogin
    case sectionLanguage, language
    case shelfTitle, shelfDropHint, shelfSwipeNote, shelfClear, shelfRemove, shelfOpen, shelfReveal

    func callAsFunction(_ lang: AppLanguage) -> String { string(lang) }

    func string(_ lang: AppLanguage) -> String {
        let entry = Self.table[self] ?? [:]
        return entry[lang] ?? entry[.english] ?? rawValue
    }

    private static let table: [L: [AppLanguage: String]] = [
        .nothingPlaying: [.english: "Nothing playing", .ukrainian: "Нічого не грає"],
        .play: [.english: "Play", .ukrainian: "Грати"],
        .pause: [.english: "Pause", .ukrainian: "Пауза"],
        .next: [.english: "Next track", .ukrainian: "Наступний трек"],
        .previous: [.english: "Previous track", .ukrainian: "Попередній трек"],
        .settings: [.english: "Settings…", .ukrainian: "Налаштування…"],
        .quit: [.english: "Quit", .ukrainian: "Вийти"],
        .openApp: [.english: "Open app", .ukrainian: "Відкрити застосунок"],
        .sectionAppearance: [.english: "Appearance", .ukrainian: "Вигляд"],
        .showCompact: [.english: "Show indicator next to the notch",
                       .ukrainian: "Показувати індикатор біля нотча"],
        .colorButtons: [.english: "Color buttons with album color",
                        .ukrainian: "Фарбувати кнопки в колір альбому"],
        .trailingIndicator: [.english: "Right of the notch",
                             .ukrainian: "Праворуч від нотча"],
        .trailingEqualizer: [.english: "Equalizer", .ukrainian: "Еквалайзер"],
        .trailingMacBattery: [.english: "Mac battery", .ukrainian: "Заряд Mac"],
        .trailingHeadphones: [.english: "Headphones battery",
                              .ukrainian: "Заряд навушників"],
        .trailingNote: [.english: "Battery rings need a connected source; otherwise the spot stays empty.",
                        .ukrainian: "Кільце заряду показується за наявності джерела; інакше місце лишається порожнім."],
        .haptic: [.english: "Haptic feedback on hover",
                  .ukrainian: "Вібрація при наведенні"],
        .hapticStrength: [.english: "Strength", .ukrainian: "Сила"],
        .hapticLight: [.english: "Light", .ukrainian: "Слабка"],
        .hapticMedium: [.english: "Medium", .ukrainian: "Середня"],
        .hapticStrong: [.english: "Strong", .ukrainian: "Сильна"],
        .sectionPeek: [.english: "Auto-peek on track change",
                       .ukrainian: "Автопоказ при зміні треку"],
        .autoPeek: [.english: "Peek when the track changes",
                    .ukrainian: "Визирати при зміні треку"],
        .autoPeekPlayPause: [.english: "Peek on play / pause",
                             .ukrainian: "Визирати при паузі / відтворенні"],
        .hideInFullscreen: [.english: "Hide near the notch in fullscreen",
                            .ukrainian: "Ховати біля нотча в повноекранному режимі"],
        .hideInFullscreenNote: [.english: "Keeps the notch out of the way while watching video.",
                                .ukrainian: "Не заважає під час перегляду відео."],
        .duration: [.english: "Duration", .ukrainian: "Тривалість"],
        .secondsSuffix: [.english: "s", .ukrainian: "с"],
        .sectionSystem: [.english: "System", .ukrainian: "Система"],
        .launchAtLogin: [.english: "Launch at login", .ukrainian: "Запускати при вході"],
        .sectionLanguage: [.english: "Language", .ukrainian: "Мова"],
        .language: [.english: "Language", .ukrainian: "Мова"],
        .shelfTitle: [.english: "File Shelf", .ukrainian: "Файлова полиця"],
        .shelfDropHint: [.english: "Drop files here", .ukrainian: "Перетягніть файли сюди"],
        .shelfSwipeNote: [.english: "They stay pinned — drag them out whenever you need.",
                          .ukrainian: "Вони залишаться тут — перетягніть далі, коли потрібно."],
        .shelfClear: [.english: "Clear", .ukrainian: "Очистити"],
        .shelfRemove: [.english: "Remove", .ukrainian: "Прибрати"],
        .shelfOpen: [.english: "Open", .ukrainian: "Відкрити"],
        .shelfReveal: [.english: "Show in Finder", .ukrainian: "Показати у Finder"],
    ]
}

/// Requests the (AppKit-managed) Settings window. Works from anywhere, including
/// the notch panel, which lives outside the app's SwiftUI scene environment.
@MainActor
func openSettingsWindow() {
    NotificationCenter.default.post(name: .openSettings, object: nil)
}
