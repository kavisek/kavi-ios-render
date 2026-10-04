//
//  CRTSettings.swift
//  render
//

import Foundation

/// Every tunable value of the CRT filter. Pixel-sized values are expressed
/// at 1080p and scaled to the video's real height, so a preset looks the
/// same at any resolution.
nonisolated struct CRTSettings: Hashable, Codable, Sendable {
    var curvature: Double
    var vignette: Double
    var scanlineIntensity: Double
    var scanlineCount: Double
    var maskIntensity: Double
    var bloom: Double
    var aberration: Double
    var softness: Double
    var noise: Double
    var flicker: Double
    var saturation: Double
    var brightness: Double

    /// Leaves the picture untouched; the starting point for custom looks.
    static let neutral = CRTSettings(
        curvature: 0, vignette: 0, scanlineIntensity: 0, scanlineCount: 240,
        maskIntensity: 0, bloom: 0, aberration: 0, softness: 0,
        noise: 0, flicker: 0, saturation: 1, brightness: 1
    )
}

// MARK: - Parameters

extension CRTSettings {
    nonisolated enum Section: String, CaseIterable, Identifiable, Sendable {
        case screen = "Screen"
        case scanlines = "Scanlines"
        case phosphor = "Phosphor"
        case signal = "Signal"
        case color = "Color"

        var id: Self { self }
        var parameters: [Parameter] { Parameter.allCases.filter { $0.section == self } }
    }

    /// Describes each setting (label, range, grouping) so the UI and the
    /// tests can be driven from one table instead of hand-written per field.
    nonisolated enum Parameter: String, CaseIterable, Identifiable, Sendable {
        case curvature, vignette
        case scanlineIntensity, scanlineCount
        case maskIntensity, bloom
        case aberration, softness, noise, flicker
        case saturation, brightness

        var id: Self { self }

        var title: String {
            switch self {
            case .curvature: "Curvature"
            case .vignette: "Vignette"
            case .scanlineIntensity: "Intensity"
            case .scanlineCount: "Line Count"
            case .maskIntensity: "Phosphor Mask"
            case .bloom: "Glow"
            case .aberration: "Color Bleed"
            case .softness: "Softness"
            case .noise: "Noise"
            case .flicker: "Flicker"
            case .saturation: "Saturation"
            case .brightness: "Brightness"
            }
        }

        var section: Section {
            switch self {
            case .curvature, .vignette: .screen
            case .scanlineIntensity, .scanlineCount: .scanlines
            case .maskIntensity, .bloom: .phosphor
            case .aberration, .softness, .noise, .flicker: .signal
            case .saturation, .brightness: .color
            }
        }

        var range: ClosedRange<Double> {
            switch self {
            case .curvature: 0...0.25
            case .vignette: 0...1
            case .scanlineIntensity: 0...1
            case .scanlineCount: 120...720
            case .maskIntensity: 0...1
            case .bloom: 0...1
            case .aberration: 0...6
            case .softness: 0...4
            case .noise: 0...0.3
            case .flicker: 0...0.3
            case .saturation: 0...2
            case .brightness: 0.5...2
            }
        }

        var step: Double? { self == .scanlineCount ? 1 : nil }

        var keyPath: WritableKeyPath<CRTSettings, Double> {
            switch self {
            case .curvature: \.curvature
            case .vignette: \.vignette
            case .scanlineIntensity: \.scanlineIntensity
            case .scanlineCount: \.scanlineCount
            case .maskIntensity: \.maskIntensity
            case .bloom: \.bloom
            case .aberration: \.aberration
            case .softness: \.softness
            case .noise: \.noise
            case .flicker: \.flicker
            case .saturation: \.saturation
            case .brightness: \.brightness
            }
        }

        func format(_ value: Double) -> String {
            switch self {
            case .scanlineCount: "\(Int(value.rounded()))"
            case .aberration, .softness: String(format: "%.1f px", value)
            default: String(format: "%.2f", value)
            }
        }
    }

    subscript(parameter: Parameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = newValue.clamped(to: parameter.range) }
    }
}

// MARK: - Presets

nonisolated struct CRTPreset: Identifiable, Hashable, Sendable {
    let name: String
    let settings: CRTSettings

    var id: String { name }

    static let livingRoomTV = CRTPreset(name: "Living Room TV", settings: CRTSettings(
        curvature: 0.10, vignette: 0.5, scanlineIntensity: 0.35, scanlineCount: 240,
        maskIntensity: 0.25, bloom: 0.35, aberration: 1.5, softness: 1.2,
        noise: 0.04, flicker: 0.03, saturation: 1.15, brightness: 1.25
    ))

    static let arcadeCabinet = CRTPreset(name: "Arcade Cabinet", settings: CRTSettings(
        curvature: 0.07, vignette: 0.35, scanlineIntensity: 0.6, scanlineCount: 224,
        maskIntensity: 0.35, bloom: 0.6, aberration: 1.0, softness: 0.8,
        noise: 0.02, flicker: 0.02, saturation: 1.35, brightness: 1.45
    ))

    static let pcMonitor = CRTPreset(name: "PC Monitor (VGA)", settings: CRTSettings(
        curvature: 0.03, vignette: 0.2, scanlineIntensity: 0.25, scanlineCount: 480,
        maskIntensity: 0.4, bloom: 0.15, aberration: 0.4, softness: 0.3,
        noise: 0.01, flicker: 0.01, saturation: 1.0, brightness: 1.2
    ))

    static let wornVHS = CRTPreset(name: "Worn VHS", settings: CRTSettings(
        curvature: 0.09, vignette: 0.6, scanlineIntensity: 0.3, scanlineCount: 240,
        maskIntensity: 0.15, bloom: 0.4, aberration: 3.5, softness: 2.5,
        noise: 0.14, flicker: 0.08, saturation: 0.8, brightness: 1.15
    ))

    static let subtle = CRTPreset(name: "Subtle", settings: CRTSettings(
        curvature: 0.04, vignette: 0.25, scanlineIntensity: 0.2, scanlineCount: 360,
        maskIntensity: 0.1, bloom: 0.2, aberration: 0.6, softness: 0.5,
        noise: 0.015, flicker: 0, saturation: 1.05, brightness: 1.1
    ))

    static let all: [CRTPreset] = [livingRoomTV, arcadeCabinet, pcMonitor, wornVHS, subtle]
    static let `default` = livingRoomTV
}

private extension Double {
    nonisolated func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
