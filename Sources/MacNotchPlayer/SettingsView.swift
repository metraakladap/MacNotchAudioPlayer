//
//  SettingsView.swift
//  MacNotchPlayer
//
//  Preferences window (⌘,) for language and player behavior.
//

import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section(prefs.t(.sectionLanguage)) {
                Picker(prefs.t(.language), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(prefs.t(.sectionAppearance)) {
                Toggle(prefs.t(.colorButtons), isOn: $prefs.colorButtons)
                Toggle(prefs.t(.showCompact), isOn: $prefs.showCompactIndicator)
                if prefs.showCompactIndicator {
                    Picker(prefs.t(.trailingIndicator), selection: $prefs.trailingIndicator) {
                        Text(prefs.t(.trailingEqualizer)).tag(TrailingIndicator.equalizer)
                        Text(prefs.t(.trailingMacBattery)).tag(TrailingIndicator.macBattery)
                        Text(prefs.t(.trailingHeadphones)).tag(TrailingIndicator.headphonesBattery)
                    }
                    if prefs.trailingIndicator != .equalizer {
                        Text(prefs.t(.trailingNote))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(prefs.t(.haptic), isOn: $prefs.hapticOnHover)
                if prefs.hapticOnHover {
                    Picker(prefs.t(.hapticStrength), selection: $prefs.hapticStrength) {
                        Text(prefs.t(.hapticLight)).tag(HapticStrength.light)
                        Text(prefs.t(.hapticMedium)).tag(HapticStrength.medium)
                        Text(prefs.t(.hapticStrong)).tag(HapticStrength.strong)
                    }
                    .pickerStyle(.segmented)
                    // Sample the chosen strength so the user can feel it.
                    .onChange(of: prefs.hapticStrength) { _, strength in
                        strength.play()
                    }
                }
            }

            Section(prefs.t(.sectionPeek)) {
                Toggle(prefs.t(.autoPeek), isOn: $prefs.autoPeekOnTrackChange)
                Toggle(prefs.t(.autoPeekPlayPause), isOn: $prefs.autoPeekOnPlayPause)
                if prefs.autoPeekOnTrackChange || prefs.autoPeekOnPlayPause {
                    HStack {
                        Text(prefs.t(.duration))
                        Slider(value: $prefs.peekDuration, in: 1...8, step: 0.5)
                        Text("\(prefs.peekDuration, specifier: "%.1f") \(prefs.t(.secondsSuffix))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(prefs.t(.hideInFullscreen), isOn: $prefs.hideInFullscreen)
                Text(prefs.t(.hideInFullscreenNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(prefs.t(.sectionSystem)) {
                Toggle(prefs.t(.launchAtLogin), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? enabled ? SMAppService.mainApp.register()
                                     : SMAppService.mainApp.unregister()
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 430, height: 460)
    }
}
