//
//  Onboarding.swift
//  MacNotchPlayer
//
//  A one-time interactive walkthrough of the File Shelf, shown on first
//  launch in a small floating card under the notch. The steps advance on the
//  user's real actions: swiping the notch open, then dropping a first file.
//

import AppKit
import SwiftUI

@MainActor
final class ShelfOnboardingController {
    private static let defaultsKey = "didShowShelfOnboarding"
    private var panel: NSPanel?
    private let ui: NotchUIState

    /// Shows the walkthrough once, shortly after launch. Returns nil when it
    /// has already been completed or skipped before.
    static func showIfNeeded(ui: NotchUIState) -> ShelfOnboardingController? {
        guard !UserDefaults.standard.bool(forKey: defaultsKey) else { return nil }
        let controller = ShelfOnboardingController(ui: ui)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            controller.show()
        }
        return controller
    }

    private init(ui: NotchUIState) {
        self.ui = ui
    }

    private func show() {
        guard panel == nil, let screen = NSScreen.screens.first else { return }

        let host = NSHostingView(rootView: ShelfOnboardingView(ui: ui, store: .shared) { [weak self] in
            self?.finish()
        })
        let size = host.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        // Centered under the notch, low enough not to overlap the expanded
        // shelf the user is about to open.
        let f = screen.frame
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                     y: f.maxY - size.height - 340))
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct ShelfOnboardingView: View {
    @ObservedObject var ui: NotchUIState
    @ObservedObject var store: ShelfStore
    @ObservedObject private var prefs = Preferences.shared
    let onFinish: () -> Void

    @State private var step = 0
    @State private var baselineCount = 0
    @State private var wave = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(prefs.t(.obTitle))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            illustration
                .frame(height: 56)

            Text(stepText)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 42, alignment: .top)

            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(.white.opacity(step == i ? 0.9 : 0.3))
                            .frame(width: 5, height: 5)
                    }
                }
                Spacer()
                if step < 2 {
                    Button(prefs.t(.obSkip), action: onFinish)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Button(action: onFinish) {
                        Text(prefs.t(.obFinish))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.18)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(width: 330)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .foregroundStyle(.white)
        .padding(12) // room for the window shadow
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                wave = true
            }
        }
        .onChange(of: ui.shelf) { _, open in
            if step == 0, open {
                baselineCount = store.items.count
                withAnimation(.smooth(duration: 0.3)) { step = 1 }
            }
        }
        .onChange(of: store.items.count) { _, count in
            if step == 1, count > baselineCount {
                withAnimation(.smooth(duration: 0.3)) { step = 2 }
            }
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch step {
        case 0:
            HStack(spacing: 14) {
                Image(systemName: "chevron.left.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 28))
                    .offset(x: wave ? 18 : -18)
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        case 1:
            VStack(spacing: 2) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 22))
                    .offset(y: wave ? 5 : -3)
                Image(systemName: "tray.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.6))
            }
        default:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.green)
        }
    }

    private var stepText: String {
        switch step {
        case 0: prefs.t(.obStepSwipe)
        case 1: prefs.t(.obStepDrop)
        default: prefs.t(.obStepDone)
        }
    }
}
