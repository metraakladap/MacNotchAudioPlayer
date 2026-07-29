//
//  CompactViews.swift
//  MacNotchPlayer
//
//  The leading/trailing content shown beside the physical notch when collapsed.
//  When the compact indicator is disabled, these collapse to an invisible 1×1
//  filler so the hover region stays active but nothing is drawn.
//

import SwiftUI

struct CompactLeading: View {
    @ObservedObject var controller: NowPlayingController
    @ObservedObject var prefs: Preferences

    var body: some View {
        if prefs.showCompactIndicator, controller.current.hasMedia {
            Group {
                if let art = controller.artwork {
                    Image(nsImage: art)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    controller.accent
                }
            }
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            CompactFiller()
        }
    }
}

struct CompactTrailing: View {
    @ObservedObject var controller: NowPlayingController
    @ObservedObject var prefs: Preferences
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        if prefs.showCompactIndicator {
            content
        } else {
            CompactFiller()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch prefs.trailingIndicator {
        case .equalizer:
            // Tied to playback: bars only while something is playing.
            if controller.current.hasMedia {
                EqualizerView(color: .white, active: controller.current.playing)
                    .frame(width: 22)
            } else {
                CompactFiller()
            }
        case .macBattery:
            // Always available.
            BatteryRingView(level: battery.macLevel,
                            charging: battery.macCharging,
                            systemImage: "laptopcomputer")
        case .headphonesBattery:
            // Only when something suitable is connected; otherwise nothing.
            if let level = battery.headphonesLevel {
                BatteryRingView(level: level, charging: false, systemImage: "headphones")
            } else {
                CompactFiller()
            }
        }
    }
}
