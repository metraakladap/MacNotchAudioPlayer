//
//  BatteryMonitor.swift
//  MacNotchPlayer
//
//  Supplies the data for the customizable trailing notch indicator:
//   - the Mac's own battery (cheap, via IOKit power sources),
//   - the connected Bluetooth headphones' battery (via `system_profiler`,
//     which is slow, so it is polled sparingly and only when selected).
//
//  iPhone battery is intentionally absent: macOS exposes no public API for a
//  connected iPhone's charge level.
//

import Combine
import Foundation
import IOKit.ps

@MainActor
final class BatteryMonitor: ObservableObject {
    /// Mac battery, 0...1.
    @Published private(set) var macLevel: Double = 1
    @Published private(set) var macCharging = false
    /// Headphones battery, 0...1, or nil when nothing suitable is connected.
    @Published private(set) var headphonesLevel: Double?

    private let prefs: Preferences
    private var timer: Timer?
    private var cancellable: AnyCancellable?

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    func start() {
        refresh()
        // Battery levels move slowly; a gentle poll keeps system_profiler cost low.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // Refresh immediately when the user switches the indicator source.
        cancellable = prefs.$trailingIndicator
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        switch prefs.trailingIndicator {
        case .equalizer: break // no data needed
        case .macBattery: refreshMac()
        case .headphonesBattery: refreshHeadphones()
        }
    }

    // MARK: - Mac battery (IOKit)

    private func refreshMac() {
        guard
            let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                macLevel = Double(current) / Double(max)
            }
            if let charging = desc[kIOPSIsChargingKey] as? Bool {
                macCharging = charging
            } else if let state = desc[kIOPSPowerSourceStateKey] as? String {
                macCharging = state == kIOPSACPowerValue
            }
        }
    }

    // MARK: - Headphones battery (system_profiler, off the main thread)

    private func refreshHeadphones() {
        Shell.runAsync("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]) { [weak self] out in
            let level = Self.parseHeadphones(Data(out.utf8))
            Task { @MainActor in
                guard let self, self.prefs.trailingIndicator == .headphonesBattery else { return }
                self.headphonesLevel = level
            }
        }
    }

    /// Picks the first connected audio device that reports a battery level.
    /// Uses the lower of left/right for earbuds, otherwise the main level.
    nonisolated static func parseHeadphones(_ data: Data) -> Double? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let section = (root["SPBluetoothDataType"] as? [[String: Any]])?.first
        else { return nil }

        func percent(_ value: Any?) -> Double? {
            guard let string = value as? String else { return nil }
            let digits = string.filter(\.isNumber)
            guard let n = Double(digits) else { return nil }
            return min(1, max(0, n / 100))
        }

        let connected = (section["device_connected"] as? [[String: Any]]) ?? []
        for entry in connected {
            for (_, value) in entry {
                guard let info = value as? [String: Any] else { continue }
                let left = percent(info["device_batteryLevelLeft"])
                let right = percent(info["device_batteryLevelRight"])
                if let left, let right { return min(left, right) }
                if let main = percent(info["device_batteryLevelMain"]) { return main }
                if let one = left ?? right { return one }
            }
        }
        return nil
    }
}
