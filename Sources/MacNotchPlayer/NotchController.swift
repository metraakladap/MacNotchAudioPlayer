//
//  NotchController.swift
//  MacNotchPlayer
//
//  Owns the DynamicNotch and translates hover + track-change events into
//  expand / compact transitions:
//   - the notch lives in the *compact* state (an album-art + equalizer pill,
//     or an invisible filler when the indicator is disabled),
//   - hovering expands it to the full player,
//   - on a track change it briefly "peeks" open, then collapses.
//

import AppKit
import Combine
import DynamicNotchKit
import SwiftUI

/// Shared UI state for the expanded notch content. `mini` shows a small
/// info-only layout (used by the auto-peek); hovering switches to the full
/// player. `shelf` swaps the expanded content for the file shelf, which stays
/// pinned open until explicitly closed.
@MainActor
final class NotchUIState: ObservableObject {
    @Published var mini = false
    @Published var shelf = false
    /// Progress (0…1) of the in-flight two-finger swipe toward opening the
    /// shelf, and its horizontal direction (+1 right / -1 left). Drives the
    /// arrow-morphs-into-tray hint at the edge of the notch content.
    @Published var swipeProgress: Double = 0
    @Published var swipeDirection: Int = 1
}

@MainActor
final class NotchController {
    private let notch: DynamicNotch<AnyView, AnyView, AnyView>
    private let prefs: Preferences
    let ui = NotchUIState()
    private var cancellables = Set<AnyCancellable>()
    private var isHovering = false
    private var hoverWatchdog: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var playPausePeekTask: Task<Void, Never>?
    private let fullscreen = FullscreenMonitor()
    private var isFullscreen = false
    private let battery: BatteryMonitor
    private var scrollMonitor: Any?
    private var swipeAccumX: CGFloat = 0
    private var swipeAccumY: CGFloat = 0
    private var swipeTriggered = false
    private var dragTimer: Timer?
    private var dragSessionChangeCount = -1
    private var dragSessionHasFiles = false
    private var shelfAutoOpenBaseline: Int?

    init(controller: NowPlayingController, prefs: Preferences) {
        self.prefs = prefs
        self.battery = BatteryMonitor(prefs: prefs)

        // Haptics are handled here (not by DynamicNotchKit) so the strength is
        // configurable live and rapid hover flapping can't buzz the trackpad.
        let ui = self.ui
        let battery = self.battery
        notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .increaseShadow],
            style: .auto,
            expanded: { AnyView(PlayerView(controller: controller, prefs: prefs, uiState: ui)) },
            compactLeading: { AnyView(CompactLeading(controller: controller, prefs: prefs)) },
            compactTrailing: { AnyView(CompactTrailing(controller: controller, prefs: prefs, battery: battery)) }
        )
        battery.start()

        // Hover → expand / compact.
        notch.$isHovering
            .removeDuplicates()
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] hovering in
                self?.handleHover(hovering)
            }
            .store(in: &cancellables)

        // Hover → haptic tap. Undebounced (must feel immediate), fires only on
        // *entry*, and is rate-limited: while the notch collapses under a
        // chasing cursor, enter/exit events flap rapidly and would otherwise
        // buzz the trackpad continuously.
        notch.$isHovering
            .removeDuplicates()
            .sink { [weak self] hovering in
                guard hovering else { return }
                self?.performHoverHaptic()
            }
            .store(in: &cancellables)

        // Track change → brief auto-peek. A track change also cancels any
        // pending play/pause peek, because switching tracks emits a transient
        // pause→play that we must NOT treat as a manual play/pause.
        controller.trackChanged
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.playPausePeekTask?.cancel()
                guard self.prefs.autoPeekOnTrackChange else { return }
                self.peek()
            }
            .store(in: &cancellables)

        // Play / pause → brief auto-peek, but deferred: if a track change lands
        // within the window the peek is cancelled (it was a track transition,
        // not a real pause/resume).
        controller.playbackToggled
            .sink { [weak self] in
                guard let self, self.prefs.autoPeekOnPlayPause else { return }
                self.playPausePeekTask?.cancel()
                self.playPausePeekTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(550))
                    guard let self, !Task.isCancelled else { return }
                    self.peek()
                }
            }
            .store(in: &cancellables)

        // Two-finger horizontal swipe across the notch → toggle the file shelf.
        // A local monitor sees scroll events delivered to our panel only.
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }

        // Auto-open the shelf when a file drag approaches the notch. NSEvent
        // monitors do NOT deliver mouse events while a drag session is in
        // progress, so this polls instead: while the left button is down, the
        // drag pasteboard says whether a file drag is active and
        // NSEvent.mouseLocation says where it is. The work per tick is trivial.
        dragTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.dragTick() }
        }

        // The shelf's close (✕) button.
        NotificationCenter.default.addObserver(
            forName: .shelfCloseRequested, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closeShelf() }
        }

        // Hide the notch while another app is fullscreen (and restore after).
        fullscreen.onChange = { [weak self] active in
            self?.handleFullscreen(active)
        }
        prefs.$hideInFullscreen
            .sink { [weak self] _ in self?.applyVisibility() }
            .store(in: &cancellables)
        fullscreen.start()
    }

    /// Show the compact pill so the hover region becomes active.
    func show() {
        Task { await notch.compact() }
    }

    /// Hidden helper for taking docs screenshots (SCREENSHOT_MODE env var):
    /// expands the notch to the player or the shelf without any interaction.
    func expandForScreenshot(shelf: Bool) {
        peekTask?.cancel()
        ui.shelf = shelf
        ui.mini = false
        Task {
            await notch.expand()
            applyShelfWindowLevel()
        }
    }

    // MARK: - File shelf

    /// How far (in scroll points) a two-finger swipe must travel to open the
    /// shelf. Long enough for the edge hint to be clearly visible mid-gesture.
    private static let swipeThreshold: CGFloat = 280

    /// Detects a deliberate two-finger horizontal swipe over the notch panel
    /// and toggles the shelf. Accumulates deltas per gesture; triggers once
    /// when horizontal movement clearly dominates.
    private func handleScroll(_ event: NSEvent) {
        guard let window = notch.windowController?.window, event.window === window else { return }
        switch event.phase {
        case .began:
            swipeAccumX = 0
            swipeAccumY = 0
            swipeTriggered = false
            ui.swipeProgress = 0
        case .changed:
            guard !swipeTriggered else { return }
            swipeAccumX += event.scrollingDeltaX
            swipeAccumY += event.scrollingDeltaY
            ui.swipeDirection = swipeAccumX >= 0 ? 1 : -1
            ui.swipeProgress = min(1, abs(swipeAccumX) / Self.swipeThreshold)
            if abs(swipeAccumX) > Self.swipeThreshold, abs(swipeAccumX) > abs(swipeAccumY) * 2 {
                swipeTriggered = true
                ui.swipeProgress = 0
                toggleShelf()
            }
        case .ended, .cancelled:
            ui.swipeProgress = 0
        default:
            break
        }
    }

    /// The drag machinery skips windows at very high levels, so the panel is
    /// lowered to `.popUpMenu` (still above normal windows) while the shelf is
    /// open, and restored to DynamicNotchKit's `.screenSaver` when it closes.
    /// Must be re-applied after every expand, because the panel window can be
    /// recreated during the transition.
    private func applyShelfWindowLevel() {
        notch.windowController?.window?.level = ui.shelf ? .popUpMenu : .screenSaver
    }

    /// Swipe on the notch: opens the shelf, or switches back to the player
    /// when the shelf is already showing.
    private func toggleShelf() {
        peekTask?.cancel()
        if ui.shelf {
            ui.shelf = false
            Task {
                if !isHovering { await notch.compact() }
                applyShelfWindowLevel()
            }
        } else {
            ui.shelf = true
            ui.mini = false
            Task {
                await notch.expand()
                applyShelfWindowLevel()
            }
        }
    }

    private func closeShelf() {
        guard ui.shelf else { return }
        ui.shelf = false
        Task {
            await notch.compact()
            ui.mini = false
            applyShelfWindowLevel()
        }
    }

    /// Tracks file drags across all apps by polling. Entering the notch zone
    /// with a file opens the shelf so it becomes a drop target; if the drag
    /// ends without anything being dropped onto it, the auto-opened shelf
    /// closes itself.
    private func dragTick() {
        let leftDown = (NSEvent.pressedMouseButtons & 1) == 1
        let pb = NSPasteboard(name: .drag)
        if pb.changeCount != dragSessionChangeCount {
            // New drag session: note whether it carries file URLs. Only counts
            // as active while the button is held (the drag pasteboard keeps
            // stale content after a session ends).
            dragSessionChangeCount = pb.changeCount
            dragSessionHasFiles = leftDown && pb.canReadObject(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            )
        }

        if leftDown {
            guard dragSessionHasFiles, !ui.shelf, mouseInNotchDropZone() else { return }
            shelfAutoOpenBaseline = ShelfStore.shared.items.count
            peekTask?.cancel()
            ui.shelf = true
            ui.mini = false
            Task {
                await notch.expand()
                applyShelfWindowLevel()
            }
        } else {
            dragSessionHasFiles = false
            guard let baseline = shelfAutoOpenBaseline else { return }
            shelfAutoOpenBaseline = nil
            // Give the async drop handler a moment to add items, then close the
            // shelf if the drag ended somewhere else.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard let self, self.ui.shelf else { return }
                if ShelfStore.shared.items.count == baseline, !self.isHovering {
                    self.closeShelf()
                }
            }
        }
    }

    /// A generous strip around the notch at the top-center of the screen.
    private func mouseInNotchDropZone() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let f = screen.frame
        let zoneWidth: CGFloat = 340
        let zoneHeight: CGFloat = 56
        let rect = NSRect(x: f.midX - zoneWidth / 2, y: f.maxY - zoneHeight,
                          width: zoneWidth, height: zoneHeight + 8)
        return rect.contains(NSEvent.mouseLocation)
    }

    private var lastHapticAt: Date = .distantPast

    /// One haptic tap per hover entry, at the configured strength, at most
    /// twice a second.
    private func performHoverHaptic() {
        guard prefs.hapticOnHover else { return }
        let now = Date()
        guard now.timeIntervalSince(lastHapticAt) > 0.5 else { return }
        lastHapticAt = now
        prefs.hapticStrength.play()
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        peekTask?.cancel()
        hoverWatchdog?.cancel()
        Task {
            if hovering {
                // Hovering always expands (player, or the shelf if it's open).
                ui.mini = false
                await notch.expand()
                applyShelfWindowLevel()
            } else if !ui.shelf {
                // The shelf stays pinned open when the mouse leaves.
                await notch.compact()
                ui.mini = false
            }
        }
        if hovering { startHoverWatchdog() }
    }

    /// Safety net for missed mouse-exit events: SwiftUI's `onHover` can drop the
    /// exit when the cursor leaves very quickly (especially mid-animation), which
    /// would leave the player stuck expanded. While we believe the mouse is over
    /// the notch, periodically verify it really is; if not, synthesize the exit
    /// so the normal hover pipeline collapses the notch.
    private func startHoverWatchdog() {
        hoverWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled, self.isHovering else { return }
                // Grown by a few points: the notch sits flush with the top
                // screen edge, where a cursor pinned against the edge reports
                // y == frame.maxY — a coordinate NSRect.contains excludes.
                if let window = self.notch.windowController?.window,
                   !window.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
                    self.notch.updateHoverState(false)
                    return
                }
            }
        }
    }

    /// Briefly slide out the *mini* (info-only) player, then collapse it again.
    private func peek() {
        guard !isHovering, !hiddenForFullscreen, !ui.shelf else { return }
        peekTask?.cancel()
        peekTask = Task {
            ui.mini = true
            await notch.expand()
            try? await Task.sleep(for: .seconds(prefs.peekDuration))
            guard !Task.isCancelled, !isHovering else { return }
            await notch.compact()
            ui.mini = false
        }
    }

    /// True when the notch should currently be hidden because of a fullscreen app.
    private var hiddenForFullscreen: Bool { isFullscreen && prefs.hideInFullscreen }

    private func handleFullscreen(_ active: Bool) {
        isFullscreen = active
        applyVisibility()
    }

    /// Reconcile the notch's visibility with the current fullscreen / hover state.
    private func applyVisibility() {
        Task {
            if hiddenForFullscreen {
                peekTask?.cancel()
                ui.mini = false
                ui.shelf = false
                await notch.hide()
            } else if isHovering || ui.shelf {
                await notch.expand()
            } else {
                await notch.compact()
            }
        }
    }
}

/// Watches for another app entering/leaving fullscreen on the notch's screen.
/// Fullscreen Spaces fire `activeSpaceDidChange`; a light poll covers the rest
/// (e.g. a video toggling fullscreen in place). Window *bounds* are readable
/// without Screen Recording permission, so no extra entitlement is needed.
@MainActor
final class FullscreenMonitor {
    var onChange: ((Bool) -> Void)?
    private(set) var isActive = false
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reevaluate() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reevaluate() }
        }
        reevaluate()
    }

    deinit {
        timer?.invalidate()
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func reevaluate() {
        let now = Self.isNotchScreenCovered()
        guard now != isActive else { return }
        isActive = now
        onChange?(now)
    }

    /// Detects a fullscreen app on the notch's screen. On a notched Mac the
    /// fullscreen window doesn't cover the top notch strip (it sits *below* it,
    /// e.g. bounds `(0, 33, 1512, 949)`), so we can't key off full height.
    /// The reliable tell is the bottom edge: a fullscreen window reaches the
    /// very bottom of the display (the Dock is hidden), while an ordinary
    /// maximized window stops above the Dock. So: a full-width layer-0 window
    /// whose bottom edge meets the screen bottom and that spans most of it.
    private static func isNotchScreenCovered() -> Bool {
        guard let screen = NSScreen.screens.first else { return false }
        let screenW = screen.frame.width
        let screenH = screen.frame.height

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            // rect is top-left origin; maxY is the bottom edge from the top.
            if rect.width >= screenW - 1,
               rect.maxY >= screenH - 1,
               rect.height >= screenH * 0.7 {
                return true
            }
        }
        return false
    }
}
