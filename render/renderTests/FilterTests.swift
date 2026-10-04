//
//  FilterTests.swift
//  renderTests
//

import AVFoundation
import CoreImage
import Testing
@testable import render

/// Reads single pixels back from Core Image output.
private struct PixelReader {
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    /// RGBA at a pixel, with (0, 0) at the bottom-left as in Core Image.
    func rgba(_ image: CIImage, x: Int, y: Int) -> SIMD4<Float> {
        var pixel = SIMD4<Float>()
        context.render(
            image, toBitmap: &pixel, rowBytes: MemoryLayout<SIMD4<Float>>.size,
            bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBAf, colorSpace: nil
        )
        return pixel
    }

    func luminance(_ image: CIImage, x: Int, y: Int) -> Float {
        let p = rgba(image, x: x, y: y)
        return (p.x + p.y + p.z) / 3
    }
}

private func solidImage(gray: Double = 0.6, width: Int = 320, height: Int = 240) -> CIImage {
    CIImage(color: CIColor(red: gray, green: gray, blue: gray))
        .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

private func gradientImage(width: Int = 320, height: Int = 240) -> CIImage {
    let gradient = CIFilter(name: "CILinearGradient", parameters: [
        "inputPoint0": CIVector(x: 0, y: 0),
        "inputPoint1": CIVector(x: CGFloat(width), y: CGFloat(height)),
        "inputColor0": CIColor(red: 0.1, green: 0.3, blue: 0.9),
        "inputColor1": CIColor(red: 0.9, green: 0.6, blue: 0.1),
    ])!.outputImage!
    return gradient.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
}

@MainActor
struct CRTFilterTests {
    private let reader = PixelReader()

    @Test func kernelCompiles() {
        #expect(CRTFilter.isAvailable, "the CRT Metal kernel failed to compile; see the 'filters' log category")
    }

    @Test func neutralSettingsLeaveTheImageUnchanged() {
        let input = gradientImage()
        let output = CRTFilter(settings: .neutral).apply(to: input, time: 0)

        for (x, y) in [(10, 10), (160, 120), (300, 220), (50, 200)] {
            let a = reader.rgba(input, x: x, y: y)
            let b = reader.rgba(output, x: x, y: y)
            #expect(abs(a - b).max() < 0.01, "pixel (\(x), \(y)) changed: \(a) -> \(b)")
        }
    }

    @Test(arguments: CRTPreset.all)
    func presetsKeepTheFrameSize(_ preset: CRTPreset) {
        let input = solidImage().transformed(by: CGAffineTransform(translationX: 40, y: 25))
        let output = CRTFilter(settings: preset.settings).apply(to: input, time: 1.5)
        #expect(output.extent == input.extent)
    }

    @Test func curvatureBlacksOutTheCorners() {
        var settings = CRTSettings.neutral
        settings.curvature = 0.2
        let output = CRTFilter(settings: settings).apply(to: solidImage(), time: 0)

        #expect(reader.luminance(output, x: 1, y: 1) < 0.01)
        #expect(reader.luminance(output, x: 318, y: 238) < 0.01)
        #expect(reader.luminance(output, x: 160, y: 120) > 0.5)
    }

    @Test func scanlinesDarkenTheGapsBetweenLines() {
        var settings = CRTSettings.neutral
        settings.scanlineIntensity = 1
        settings.scanlineCount = 24 // 10 px per line on a 240 px frame
        let output = CRTFilter(settings: settings).apply(to: solidImage(), time: 0)

        let lineCentre = reader.luminance(output, x: 160, y: 4)
        let gap = reader.luminance(output, x: 160, y: 9)
        #expect(lineCentre > 0.5)
        #expect(gap < lineCentre * 0.2, "gap \(gap) vs line \(lineCentre)")
    }

    @Test func phosphorMaskTintsNeighbouringColumns() {
        var settings = CRTSettings.neutral
        settings.maskIntensity = 1
        let output = CRTFilter(settings: settings).apply(to: solidImage(), time: 0)

        let columns = (0..<3).map { reader.rgba(output, x: 150 + $0, y: 120) }
        // Each column of a triad lets through only one primary.
        for (index, pixel) in columns.enumerated() {
            let channels = [pixel.x, pixel.y, pixel.z]
            let lit = channels.indices.filter { channels[$0] > 0.3 }
            #expect(lit.count == 1, "column \(index) lit channels: \(channels)")
        }
        #expect(Set(columns.map { [$0.x, $0.y, $0.z].firstIndex(of: max($0.x, $0.y, $0.z))! }).count == 3)
    }

    @Test func brightnessScalesTheImage() {
        var settings = CRTSettings.neutral
        settings.brightness = 0.5
        let output = CRTFilter(settings: settings).apply(to: solidImage(gray: 0.6), time: 0)
        let ratio = reader.luminance(output, x: 160, y: 120) / reader.luminance(solidImage(gray: 0.6), x: 160, y: 120)
        #expect(abs(ratio - 0.5) < 0.02)
    }
}

@MainActor
struct CRTSettingsTests {

    @Test func presetsStayWithinParameterRanges() {
        for preset in CRTPreset.all {
            for parameter in CRTSettings.Parameter.allCases {
                #expect(parameter.range.contains(preset.settings[parameter]), "\(preset.name).\(parameter)")
            }
        }
    }

    @Test func presetNamesAreUnique() {
        #expect(Set(CRTPreset.all.map(\.id)).count == CRTPreset.all.count)
        #expect(CRTPreset.all.contains(CRTPreset.default))
    }

    @Test func everyParameterBelongsToOneSection() {
        let grouped = CRTSettings.Section.allCases.flatMap(\.parameters)
        #expect(grouped.count == CRTSettings.Parameter.allCases.count)
        #expect(Set(grouped) == Set(CRTSettings.Parameter.allCases))
    }

    @Test func subscriptClampsToTheParameterRange() {
        var settings = CRTSettings.neutral
        settings[.curvature] = 5
        settings[.brightness] = -1
        #expect(settings.curvature == CRTSettings.Parameter.curvature.range.upperBound)
        #expect(settings.brightness == CRTSettings.Parameter.brightness.range.lowerBound)
    }
}

@MainActor
struct VideoPlayerModelFilterTests {

    @Test func filterStartsOffWithTheDefaultPreset() {
        let model = VideoPlayerModel()
        #expect(!model.isFilterEnabled)
        #expect(model.crtSettings == CRTPreset.default.settings)
        #expect(model.matchingPreset == CRTPreset.default)
        #expect(model.filterPipeline.filter == nil)
    }

    @Test func enablingTheFilterActivatesItWithTheCurrentSettings() throws {
        let model = VideoPlayerModel()
        model.isFilterEnabled = true
        let filter = try #require(model.filterPipeline.filter as? CRTFilter)
        #expect(filter.settings == model.crtSettings)

        model.crtSettings.curvature = 0.2
        #expect((model.filterPipeline.filter as? CRTFilter)?.settings.curvature == 0.2)

        model.isFilterEnabled = false
        #expect(model.filterPipeline.filter == nil)
    }

    @Test func tweakingAParameterMakesACustomLookThatResetRestores() {
        let model = VideoPlayerModel()
        model.applyPreset(.arcadeCabinet)
        #expect(model.matchingPreset == .arcadeCabinet)

        model.crtSettings[.noise] = 0.25
        #expect(model.matchingPreset == nil)

        model.resetToBasePreset()
        #expect(model.crtSettings == CRTPreset.arcadeCabinet.settings)
        #expect(model.matchingPreset == .arcadeCabinet)
    }
}

/// Plays real video through the composition and reads the frames AVPlayer
/// actually produces, so these cover the whole path from settings to pixels.
@MainActor
struct VideoFilterPipelineTests {

    private func waitForComposition(_ model: VideoPlayerModel) async throws -> AVPlayerItem {
        let item = try #require(model.player?.currentItem)
        let attached = await waitUntil { item.videoComposition != nil && item.status == .readyToPlay }
        try #require(attached, "the filter composition was never attached")
        return item
    }

    /// Mean brightness (0–255) of a small square of a BGRA frame; `y` is
    /// measured from the top of the frame.
    private func brightness(of buffer: CVPixelBuffer, x: Int, y: Int, size: Int = 4) -> Double {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var total = 0
        for row in y..<(y + size) {
            for column in x..<(x + size) {
                let pixel = base + row * rowBytes + column * 4
                total += Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2])
            }
        }
        return Double(total) / Double(size * size * 3)
    }

    private func latestFrame(from output: AVPlayerItemVideoOutput, item: AVPlayerItem) async -> CVPixelBuffer? {
        var frame: CVPixelBuffer?
        _ = await waitUntil {
            let time = item.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time) {
                frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
            }
            return frame != nil
        }
        return frame
    }

    @Test func playbackFramesGoThroughTheFilter() async throws {
        let url = try await VideoFixture.makeMP4(seconds: 6)
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        model.load(url: url)
        let item = try await waitForComposition(model)

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)

        // Off: frames pass through, corners keep the grey picture.
        let plain = try #require(await latestFrame(from: output, item: item))
        #expect(brightness(of: plain, x: 0, y: 0) > 100)

        // On with strong curvature: the corners fall off the curved glass.
        var settings = CRTSettings.neutral
        settings.curvature = 0.2
        model.crtSettings = settings
        model.isFilterEnabled = true
        try await Task.sleep(for: .milliseconds(300)) // let pre-filter frames drain

        let filtered = try #require(await latestFrame(from: output, item: item))
        let width = CVPixelBufferGetWidth(filtered), height = CVPixelBufferGetHeight(filtered)
        #expect(brightness(of: filtered, x: 0, y: 0) < 5)
        #expect(brightness(of: filtered, x: width - 4, y: height - 4) < 5)
        #expect(brightness(of: filtered, x: width / 2, y: height / 2) > 100)
        #expect(model.filterPipeline.framesRendered > 0)
    }

    @Test func changingSettingsWhilePausedRedrawsTheFrame() async throws {
        let url = try await VideoFixture.makeMP4()
        defer { try? FileManager.default.removeItem(at: url) }

        let model = VideoPlayerModel()
        model.load(url: url)
        let item = try await waitForComposition(model)
        // Something has to consume frames, as AVPlayerView does in the app.
        item.add(AVPlayerItemVideoOutput(pixelBufferAttributes: nil))
        model.player?.pause()
        model.isFilterEnabled = true
        try await Task.sleep(for: .milliseconds(300))

        let before = model.filterPipeline.framesRendered
        model.crtSettings[.scanlineIntensity] = 0.9

        let redrew = await waitUntil { model.filterPipeline.framesRendered > before }
        #expect(redrew, "a paused frame was not re-rendered after a settings change")
    }
}
