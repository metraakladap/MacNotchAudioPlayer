//
//  ArtworkColor.swift
//  MacNotchPlayer
//
//  Samples a vibrant accent color from album artwork and resolves the icon of
//  the app that is currently playing.
//

import AppKit
import SwiftUI

enum ArtworkColor {
    /// Returns a saturated accent color sampled from the average of `image`.
    static func accent(from image: NSImage) -> Color {
        guard let avg = averageColor(of: image) else { return .purple }
        // Boost saturation/brightness so the tint reads well on the black notch.
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        let rgb = avg.usingColorSpace(.sRGB) ?? avg
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        s = min(1.0, max(0.75, s * 1.7))
        b = min(1.0, max(0.78, b * 1.35))
        return Color(nsColor: NSColor(hue: h, saturation: s, brightness: b, alpha: 1))
    }

    private static func averageColor(of image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }

        let width = 8, height = 8
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var r = 0.0, g = 0.0, b = 0.0
        let count = width * height
        for i in 0..<count {
            r += Double(pixels[i * 4]); g += Double(pixels[i * 4 + 1]); b += Double(pixels[i * 4 + 2])
        }
        return NSColor(
            srgbRed: r / Double(count) / 255.0,
            green: g / Double(count) / 255.0,
            blue: b / Double(count) / 255.0,
            alpha: 1
        )
    }
}

enum SourceApp {
    private static var iconCache: [String: NSImage] = [:]

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = iconCache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[bundleID] = icon
        return icon
    }

    static func open(bundleID: String?) {
        guard let bundleID, !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
