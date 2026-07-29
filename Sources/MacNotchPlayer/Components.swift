//
//  Components.swift
//  MacNotchPlayer
//
//  Small reusable views: a marquee (auto-scrolling) label and an animated
//  audio equalizer.
//

import SwiftUI

/// A single-line label that gently scrolls back and forth when the text is
/// wider than the available space.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 15, weight: .semibold)

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(0, textWidth - containerWidth) }

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }
                .offset(x: offset)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .onAppear { containerWidth = geo.size.width }
                .onChange(of: geo.size.width) { _, w in containerWidth = w }
        }
        .frame(height: lineHeight)
        // Keyed by text and (rounded) overflow: any change cancels the running
        // scroll loop and starts a fresh one from the beginning of the line.
        .task(id: "\(text)|\(Int(overflow.rounded()))") { await scrollLoop() }
    }

    private var lineHeight: CGFloat { 20 }

    private func scrollLoop() async {
        // Snap back to the start of the line, discarding any in-flight
        // animation left over from the previous title or width.
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { offset = 0 }

        guard overflow > 1 else { return }
        let distance = overflow + 8
        let duration = Double(distance) / 30.0 // ~30 pts/sec

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: duration)) { offset = -distance }
            try? await Task.sleep(nanoseconds: UInt64((duration + 1.2) * 1_000_000_000))
            if Task.isCancelled { return }
            withAnimation(.easeInOut(duration: duration)) { offset = 0 }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }
    }
}

/// A small circular battery gauge for the trailing notch slot: a faint track,
/// a colored arc proportional to the charge, and a device glyph in the center.
struct BatteryRingView: View {
    var level: Double          // 0...1
    var charging: Bool
    var systemImage: String    // center glyph (e.g. "laptopcomputer", "headphones")

    private var tint: Color {
        if charging { return .green }
        if level <= 0.2 { return .red }
        return .white
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.22), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, level)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
        .animation(.easeInOut(duration: 0.3), value: level)
        .animation(.easeInOut(duration: 0.3), value: charging)
    }
}

/// An animated equalizer used in the compact notch state.
struct EqualizerView: View {
    var color: Color
    var active: Bool
    var barCount: Int = 4

    private let barWidth: CGFloat = 2.5
    private let maxHeight: CGFloat = 13
    private let minHeight: CGFloat = 3

    var body: some View {
        if active {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                bars { height(for: $0, t: t) }
            }
        } else {
            bars { _ in minHeight + 1 }
        }
    }

    private func bars(_ height: @escaping (Int) -> CGFloat) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(color)
                    .frame(width: barWidth, height: height(i))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.12), value: active)
    }

    private func height(for index: Int, t: Double) -> CGFloat {
        let phase = Double(index) * 0.9
        let v = (sin(t * 7 + phase) + 1) / 2 // 0...1
        return minHeight + CGFloat(v) * (maxHeight - minHeight)
    }
}
