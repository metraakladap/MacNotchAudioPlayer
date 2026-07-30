//
//  PlayerView.swift
//  MacNotchPlayer
//
//  The expanded player shown below the notch, styled with macOS 26 Liquid Glass.
//  Transport buttons optionally take the album's color (applied immediately via
//  `.glassEffect(.tint)`, no click required); sliders stay neutral.
//

import SwiftUI

struct PlayerView: View {
    @ObservedObject var controller: NowPlayingController
    @ObservedObject var prefs: Preferences
    @ObservedObject var uiState: NotchUIState

    @State private var dragValue: Double = 0
    @State private var isDragging = false
    @State private var showRemaining = false
    @State private var volumeDrag: Double = 0
    @State private var isVolumeDragging = false

    private var np: NowPlaying { controller.current }
    private var duration: Double { max(np.duration, 0.01) }
    private var sliderValue: Double {
        isDragging ? dragValue : min(max(controller.displayedElapsed, 0), duration)
    }
    private var volumeValue: Double { isVolumeDragging ? volumeDrag : controller.volume }
    private var swipeHintActive: Bool { uiState.swipeProgress > 0.05 && !uiState.shelf }
    private var accent: Color { controller.accent }
    private var colored: Bool { prefs.colorButtons }

    var body: some View {
        Group {
            if uiState.shelf {
                FileShelfView(store: .shared, prefs: prefs)
            } else if uiState.mini && np.hasMedia {
                miniView
            } else {
                fullView
            }
        }
        .animation(.smooth(duration: 0.35), value: uiState.mini)
        .animation(.smooth(duration: 0.35), value: uiState.shelf)
        // Two-finger swipe hint: while the gesture is in flight the pill grows
        // sideways, giving the hint its own margin *outside* the content, where
        // an arrow morphs into the shelf icon as the swipe nears the threshold.
        .padding(.horizontal, swipeHintActive ? 42 : 0)
        .overlay(alignment: uiState.swipeDirection > 0 ? .trailing : .leading) {
            if swipeHintActive {
                SwipeShelfHint(progress: uiState.swipeProgress,
                               direction: uiState.swipeDirection)
                    .padding(.horizontal, 10)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.25), value: swipeHintActive)
    }

    private var fullView: some View {
        VStack(spacing: 14) {
            header
            if np.hasMedia {
                scrubber
                controls
                volumeRow
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 400)
        .foregroundStyle(.white)
    }

    // MARK: - Mini (auto-peek) layout — track info only, compact footprint.

    private var miniView: some View {
        HStack(spacing: 11) {
            Group {
                if let image = controller.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(white: 0.3), Color(white: 0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note").font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: np.title ?? prefs.t(.nothingPlaying),
                            font: .system(size: 13, weight: .semibold))
                    .frame(height: 18)
                if let artist = np.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            if controller.current.playing {
                EqualizerView(color: .white, active: true).frame(width: 18)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(width: 250)
        .foregroundStyle(.white)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 13) {
            artwork
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: np.title ?? prefs.t(.nothingPlaying))
                    .frame(height: 20)
                if let artist = np.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
                HStack(spacing: 5) {
                    if let icon = SourceApp.icon(forBundleID: np.bundleIdentifier) {
                        Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                    }
                    if let album = np.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            settingsButton
        }
    }

    private var settingsButton: some View {
        Button {
            openSettingsWindow()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(prefs.t(.settings))
    }

    private var artwork: some View {
        Button {
            SourceApp.open(bundleID: np.bundleIdentifier)
        } label: {
            Group {
                if let image = controller.artwork {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        LinearGradient(colors: [Color(white: 0.3), Color(white: 0.18)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Image(systemName: "music.note")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .help(prefs.t(.openApp))
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(spacing: 3) {
            Slider(
                value: Binding(get: { sliderValue }, set: { dragValue = $0 }),
                in: 0...duration,
                onEditingChanged: { editing in
                    if editing {
                        isDragging = true
                        controller.isScrubbing = true
                    } else {
                        controller.seek(toSeconds: dragValue)
                        isDragging = false
                        controller.isScrubbing = false
                    }
                }
            )
            .controlSize(.small)
            .tint(.white)

            HStack {
                Text(formatTime(sliderValue))
                Spacer()
                Text(showRemaining ? "-\(formatTime(max(0, duration - sliderValue)))" : formatTime(duration))
                    .onTapGesture { showRemaining.toggle() }
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Transport controls

    private var controls: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                GlassCircleButton(system: "shuffle", size: 13, on: np.shuffleOn,
                                  colored: colored, accent: accent) {
                    controller.toggleShuffle()
                }
                GlassCircleButton(system: "backward.fill", size: 15,
                                  colored: colored, accent: accent) {
                    controller.previousTrack()
                }
                GlassCircleButton(system: np.playing ? "pause.fill" : "play.fill",
                                  size: 22, prominent: true,
                                  colored: colored, accent: accent) {
                    controller.togglePlayPause()
                }
                GlassCircleButton(system: "forward.fill", size: 15,
                                  colored: colored, accent: accent) {
                    controller.nextTrack()
                }
                GlassCircleButton(system: (np.repeatMode == 2) ? "repeat.1" : "repeat",
                                  size: 13, on: np.repeatOn,
                                  colored: colored, accent: accent) {
                    controller.cycleRepeat()
                }
            }
        }
    }

    // MARK: - Volume

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
            Slider(
                value: Binding(
                    get: { volumeValue },
                    set: { newValue in
                        volumeDrag = newValue
                        controller.setVolumeLive(newValue)
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    if editing {
                        isVolumeDragging = true
                        controller.isAdjustingVolume = true
                    } else {
                        controller.setVolume(volumeDrag)
                        isVolumeDragging = false
                        controller.isAdjustingVolume = false
                    }
                }
            )
            .controlSize(.mini)
            .tint(.white)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
    }
}

/// A circular Liquid Glass transport button. When `colored` is on, its glass is
/// tinted with the album color immediately (no interaction needed). `on`
/// indicates an active toggle (shuffle/repeat) and forces the tint.
private struct GlassCircleButton: View {
    let system: String
    var size: CGFloat = 15
    var prominent: Bool = false
    var on: Bool = false
    var colored: Bool
    var accent: Color
    let action: () -> Void

    private var padding: CGFloat { prominent ? 24 : 18 }

    var body: some View {
        // Buttons take the album color when color mode is on, or when this is an
        // active toggle (shuffle/repeat). The fill sits behind the glass so the
        // color is visible immediately, with a glassy rim on top.
        let tinted = colored || on
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + padding, height: size + padding)
                .background {
                    if tinted {
                        Circle().fill(accent.gradient)
                            .opacity(prominent ? 0.95 : 0.8)
                    }
                }
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

/// Near-invisible compact filler that keeps the notch hover region active.
struct CompactFiller: View {
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
    }
}
