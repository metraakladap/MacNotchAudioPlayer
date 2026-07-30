//
//  FileShelf.swift
//  MacNotchPlayer
//
//  A pinned "shelf" under the notch: two-finger swipe across the notch opens
//  it, files dragged onto it stay attached (persisted across launches), and
//  can later be dragged out to Finder or any app — a quick drag-and-drop tray.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Notification.Name {
    static let shelfCloseRequested = Notification.Name("MacNotchPlayer.shelfCloseRequested")
}

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
}

/// The shelf's contents, persisted as file paths in UserDefaults. Files that
/// no longer exist on disk are dropped on load.
@MainActor
final class ShelfStore: ObservableObject {
    static let shared = ShelfStore()

    @Published private(set) var items: [ShelfItem] = []
    private let defaultsKey = "shelfItems"

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths
            .map { ShelfItem(id: UUID(), url: URL(fileURLWithPath: $0)) }
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
    }

    func add(_ url: URL) {
        guard !items.contains(where: { $0.url.path == url.path }) else { return }
        items.append(ShelfItem(id: UUID(), url: url))
        save()
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.url.path), forKey: defaultsKey)
    }
}

/// The expanded-notch shelf UI: a drop zone when empty, a grid of draggable
/// file tiles once files are attached.
struct FileShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var prefs: Preferences

    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 10) {
            header
            if store.items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 400)
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(dropTargeted ? 0.6 : 0), lineWidth: 2)
                .padding(6)
                .animation(.easeOut(duration: 0.15), value: dropTargeted)
                .allowsHitTesting(false)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(prefs.t(.shelfTitle))
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if !store.items.isEmpty {
                // A visually distinct capsule so it can't be confused with the
                // close (✕) icon next to it.
                Button {
                    store.clear()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 9, weight: .semibold))
                        Text(prefs.t(.shelfClear))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(.white.opacity(0.2))
                    .frame(width: 1, height: 14)
                    .padding(.horizontal, 4)
            }
            Button {
                NotificationCenter.default.post(name: .shelfCloseRequested, object: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Text(prefs.t(.shelfDropHint))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            Text(prefs.t(.shelfSwipeNote))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 96)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.white.opacity(0.25))
        )
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                ForEach(store.items) { item in
                    ShelfItemCell(item: item, prefs: prefs) {
                        store.remove(item)
                    }
                }
            }
        }
        .frame(maxHeight: 190)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }
        for provider in fileProviders {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in ShelfStore.shared.add(url) }
            }
        }
        return true
    }
}

/// The hint shown during a two-finger swipe: a notch-black droplet that slides
/// out from the swipe-side edge, with an arrow that crossfades into the
/// shelf's tray icon as the gesture nears the trigger threshold.
struct SwipeShelfHint: View {
    var progress: Double
    var direction: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black)
                .frame(width: 78, height: 78)
            ZStack {
                Image(systemName: direction > 0 ? "arrow.right" : "arrow.left")
                    .opacity(1 - progress)
                Image(systemName: "tray.full.fill")
                    .opacity(progress)
            }
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
        }
        // Grows from the attachment side, so it reads as a drop forming on
        // the edge rather than a box fading in.
        .scaleEffect(0.55 + 0.45 * progress,
                     anchor: direction > 0 ? .leading : .trailing)
        .animation(.linear(duration: 0.06), value: progress)
    }
}

/// One attached file: icon + name, draggable out, removable on hover,
/// double-click to open.
private struct ShelfItemCell: View {
    let item: ShelfItem
    let prefs: Preferences
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 40, height: 40)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .frame(width: 76)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(hovering ? 0.12 : 0.06))
        )
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8), .black.opacity(0.6))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(2)
            }
        }
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .contextMenu {
            Button(prefs.t(.shelfOpen)) { NSWorkspace.shared.open(item.url) }
            Button(prefs.t(.shelfReveal)) {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button(prefs.t(.shelfRemove), role: .destructive, action: onRemove)
        }
        .help(item.url.lastPathComponent)
    }
}
