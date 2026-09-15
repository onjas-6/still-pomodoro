#!/usr/bin/env swift
// Created 2026-09-15 · gpt-5.6-terra · Codex
// Generates Still's original icon and synthesized chime using only macOS frameworks.

import AppKit
import AVFoundation
import AudioToolbox
import Foundation

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let projectURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let resourcesURL = projectURL.appendingPathComponent("Resources", isDirectory: true)
let previewURL = resourcesURL.appendingPathComponent("AppIcon.png")
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
let chimeURL = resourcesURL.appendingPathComponent("StillChime.aiff")

try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha
        )
    }
}

func squircle(in rect: NSRect, exponent: CGFloat = 4.6) -> NSBezierPath {
    let path = NSBezierPath()
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let radiusX = rect.width / 2
    let radiusY = rect.height / 2
    let steps = 360

    for step in 0...steps {
        let theta = CGFloat(step) / CGFloat(steps) * .pi * 2
        let cosine = cos(theta)
        let sine = sin(theta)
        let x = center.x + radiusX * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / exponent)
        let y = center.y + radiusY * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / exponent)
        let point = NSPoint(x: x, y: y)
        if step == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    return path
}

func leaf(from base: NSPoint, tip: NSPoint, upperControl: NSPoint, lowerControl: NSPoint) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: base)
    path.curve(to: tip, controlPoint1: upperControl, controlPoint2: NSPoint(x: tip.x * 0.82 + upperControl.x * 0.18, y: tip.y * 0.82 + upperControl.y * 0.18))
    path.curve(to: base, controlPoint1: lowerControl, controlPoint2: NSPoint(x: base.x * 0.75 + lowerControl.x * 0.25, y: base.y * 0.75 + lowerControl.y * 0.25))
    path.close()
    return path
}

func drawIcon() {
    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    let tile = squircle(in: NSRect(x: 36, y: 36, width: 952, height: 952))

    let baseGradient = NSGradient(colors: [
        NSColor(hex: 0xFBF9F1),
        NSColor(hex: 0xF5F2E8),
        NSColor(hex: 0xEDE8D9)
    ])!
    baseGradient.draw(in: tile, angle: -48)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let glow = NSBezierPath(ovalIn: NSRect(x: 138, y: 625, width: 618, height: 414))
    NSColor.white.withAlphaComponent(0.22).setFill()
    glow.fill()
    let warmShade = NSBezierPath(ovalIn: NSRect(x: 470, y: -90, width: 670, height: 560))
    NSColor(hex: 0xD8CFB7, alpha: 0.10).setFill()
    warmShade.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(hex: 0xC9C2AC, alpha: 0.60).setStroke()
    tile.lineWidth = 2
    tile.stroke()

    let ring = NSBezierPath(ovalIn: NSRect(x: 223, y: 223, width: 578, height: 578))
    ring.lineWidth = 5.5
    ring.lineCapStyle = .round
    NSColor(hex: 0x77866C, alpha: 0.72).setStroke()
    ring.stroke()

    let center = NSPoint(x: 512, y: 512)
    let progressAngle: CGFloat = .pi / 3
    let dotCenter = NSPoint(x: center.x + 289 * cos(progressAngle), y: center.y + 289 * sin(progressAngle))
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(hex: 0x94753B, alpha: 0.26)
    shadow.shadowBlurRadius = 9
    shadow.shadowOffset = NSSize(width: 0, height: -2)
    shadow.set()
    NSColor(hex: 0xB58A43).setFill()
    NSBezierPath(ovalIn: NSRect(x: dotCenter.x - 13, y: dotCenter.y - 13, width: 26, height: 26)).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor(hex: 0xE1C685, alpha: 0.86).setFill()
    NSBezierPath(ovalIn: NSRect(x: dotCenter.x - 6, y: dotCenter.y - 5, width: 9, height: 9)).fill()

    let green = NSColor(hex: 0x294538)
    let stem = NSBezierPath()
    stem.move(to: NSPoint(x: 498, y: 385))
    stem.curve(to: NSPoint(x: 530, y: 642), controlPoint1: NSPoint(x: 504, y: 455), controlPoint2: NSPoint(x: 511, y: 572))
    stem.lineWidth = 8
    stem.lineCapStyle = .round
    green.setStroke()
    stem.stroke()

    let leftLeaf = leaf(
        from: NSPoint(x: 512, y: 500),
        tip: NSPoint(x: 365, y: 590),
        upperControl: NSPoint(x: 430, y: 579),
        lowerControl: NSPoint(x: 434, y: 465)
    )
    green.setFill()
    leftLeaf.fill()

    let rightLeaf = leaf(
        from: NSPoint(x: 521, y: 548),
        tip: NSPoint(x: 662, y: 674),
        upperControl: NSPoint(x: 593, y: 685),
        lowerControl: NSPoint(x: 628, y: 546)
    )
    rightLeaf.fill()

    let leftVein = NSBezierPath()
    leftVein.move(to: NSPoint(x: 503, y: 505))
    leftVein.curve(to: NSPoint(x: 384, y: 580), controlPoint1: NSPoint(x: 466, y: 533), controlPoint2: NSPoint(x: 420, y: 560))
    leftVein.lineWidth = 3
    leftVein.lineCapStyle = .round
    NSColor(hex: 0xF5F2E8, alpha: 0.42).setStroke()
    leftVein.stroke()

    let rightVein = NSBezierPath()
    rightVein.move(to: NSPoint(x: 527, y: 555))
    rightVein.curve(to: NSPoint(x: 646, y: 662), controlPoint1: NSPoint(x: 570, y: 590), controlPoint2: NSPoint(x: 615, y: 632))
    rightVein.lineWidth = 3
    rightVein.lineCapStyle = .round
    NSColor(hex: 0xF5F2E8, alpha: 0.42).setStroke()
    rightVein.stroke()

    _ = canvas
}

func pngData(pixelSize: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "StillAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create icon bitmap."])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setAllowsAntialiasing(true)
    context.cgContext.setShouldAntialias(true)
    context.cgContext.interpolationQuality = CGInterpolationQuality.high
    context.cgContext.clear(NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    context.cgContext.scaleBy(x: CGFloat(pixelSize) / 1024, y: CGFloat(pixelSize) / 1024)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "StillAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG."])
    }
    return data
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

func writeICNSFallback(to destination: URL) throws {
    // Current ICNS stores PNG payloads. Include every unique pixel size represented
    // by the standard iconset (the @2x entries share the matching target size).
    let chunks: [(String, Int)] = [
        ("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128),
        ("ic08", 256), ("ic09", 512), ("ic10", 1024)
    ]
    var icns = Data("icns".utf8)
    appendBigEndian(0, to: &icns) // Filled after all chunks are appended.
    for (type, size) in chunks {
        let image = try pngData(pixelSize: size)
        icns.append(Data(type.utf8))
        appendBigEndian(UInt32(image.count + 8), to: &icns)
        icns.append(image)
    }
    let totalLength = UInt32(icns.count).bigEndian
    withUnsafeBytes(of: totalLength) { bytes in
        icns.replaceSubrange(4..<8, with: bytes)
    }
    try icns.write(to: destination, options: .atomic)
}

func createIcon() throws {
    try pngData(pixelSize: 1024).write(to: previewURL, options: .atomic)

    let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("Still-AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset", isDirectory: true)
    try? fileManager.removeItem(at: iconsetURL)
    try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: iconsetURL) }

    let iconSizes: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]
    for (name, size) in iconSizes {
        try pngData(pixelSize: size).write(to: iconsetURL.appendingPathComponent(name), options: .atomic)
    }

    try? fileManager.removeItem(at: icnsURL)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", "-o", icnsURL.path, iconsetURL.path]
    task.standardOutput = Pipe()
    task.standardError = Pipe()
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 || !fileManager.fileExists(atPath: icnsURL.path) {
        // iconutil is occasionally unable to reassemble valid PNG iconsets on
        // current macOS releases. Keep a self-contained fallback with the same
        // ICNS chunk layout so builds stay reproducible.
        try? fileManager.removeItem(at: icnsURL)
        try writeICNSFallback(to: icnsURL)
    }
}

struct BellTone {
    let frequency: Float
    let onset: Float
    let amplitude: Float
    let decay: Float
    let phase: Float
}

func softEnvelope(_ t: Float, decay: Float) -> Float {
    let attack = min(1, t / 0.035)
    let roundedAttack = sin(attack * .pi / 2)
    return roundedAttack * exp(-t / decay)
}

func chimeSample(t: Float, tone: BellTone) -> Float {
    let localTime = t - tone.onset
    guard localTime >= 0 else { return 0 }
    let phase = 2 * Float.pi * tone.frequency * localTime + tone.phase
    let shimmer =
        0.76 * sin(phase) +
        0.15 * sin(phase * 2.01 + 0.35) +
        0.060 * sin(phase * 3.08 + 0.80) +
        0.022 * sin(phase * 4.32 + 1.14)
    return tone.amplitude * softEnvelope(localTime, decay: tone.decay) * shimmer
}

func createChime() throws -> Float {
    let sampleRate: Double = 44_100
    let duration: Float = 2.25
    let frames = Int((Double(duration) * sampleRate).rounded(.up))
    let tones = [
        BellTone(frequency: 659.255, onset: 0.000, amplitude: 0.38, decay: 0.80, phase: 0.22), // E5
        BellTone(frequency: 987.767, onset: 0.165, amplitude: 0.29, decay: 0.72, phase: 0.68)  // B5
    ]
    var samples = [Float](repeating: 0, count: frames)
    var peak: Float = 0
    for index in samples.indices {
        let time = Float(Double(index) / sampleRate)
        let value = tones.reduce(Float.zero) { $0 + chimeSample(t: time, tone: $1) } * 0.50
        samples[index] = value
        peak = max(peak, abs(value))
    }
    guard peak < 0.95 else {
        throw NSError(domain: "StillAssets", code: 4, userInfo: [NSLocalizedDescriptionKey: "Chime would clip (peak \(peak))."])
    }

    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: true,
        AVLinearPCMIsNonInterleaved: false
    ]
    try? fileManager.removeItem(at: chimeURL)
    let file = try AVAudioFile(forWriting: chimeURL, settings: settings)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames)),
          let channel = buffer.floatChannelData?[0] else {
        throw NSError(domain: "StillAssets", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unable to allocate audio buffer."])
    }
    for index in samples.indices { channel[index] = samples[index] }
    buffer.frameLength = AVAudioFrameCount(frames)
    try file.write(from: buffer)
    return peak
}

do {
    try createIcon()
    let peak = try createChime()
    print("Generated AppIcon.png (1024×1024), AppIcon.icns, and StillChime.aiff (44.1 kHz PCM 16-bit, peak \(String(format: "%.4f", peak))).")
} catch {
    fputs("Asset generation failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
