//
//  App.swift
//  MacNotchPlayer
//
//  Menu-bar agent (LSUIElement) that boots the now-playing stream and the
//  notch UI. The Settings window is managed manually (AppKit) so it opens
//  reliably from both the menu and the in-notch gear button.
//

import ServiceManagement
import SwiftUI

extension Notification.Name {
    static let openSettings = Notification.Name("MacNotchPlayer.openSettings")
}

@main
struct MacNotchPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Notch Player", systemImage: "music.note.list") {
            MenuContent(controller: appDelegate.nowPlaying)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let nowPlaying = NowPlayingController()
    private var notchController: NotchController?
    private var settingsWindow: NSWindow?
    private var onboarding: ShelfOnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        nowPlaying.start()
        notchController = NotchController(controller: nowPlaying, prefs: .shared)
        notchController?.show()
        registerLoginItemIfFirstLaunch()
        if let notchController {
            onboarding = ShelfOnboardingController.showIfNeeded(ui: notchController.ui)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(showSettings),
            name: .openSettings, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying.stop()
    }

    @objc func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(prefs: .shared))
            let window = NSWindow(contentViewController: host)
            window.title = "MacNotchPlayer"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                Task { @MainActor in NSApp.setActivationPolicy(.accessory) }
            }
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func registerLoginItemIfFirstLaunch() {
        let key = "didRegisterLoginItem"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// Contents of the menu-bar dropdown.
struct MenuContent: View {
    @ObservedObject var controller: NowPlayingController
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        Text(controller.current.hasMedia ? controller.current.menuLabel : prefs.t(.nothingPlaying))

        Divider()

        Button(controller.current.playing ? prefs.t(.pause) : prefs.t(.play)) {
            controller.togglePlayPause()
        }
        Button(prefs.t(.next)) { controller.nextTrack() }
        Button(prefs.t(.previous)) { controller.previousTrack() }

        Divider()

        Button(prefs.t(.settings)) { openSettingsWindow() }
            .keyboardShortcut(",")
        Button(prefs.t(.quit)) { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
