//
//  VideoFixture.swift
//  TestSupport (shared by renderTests and renderUITests)
//

import AVFoundation
import CoreVideo
import Foundation

/// Generates small throwaway media files so tests don't depend on a real
/// video being checked into the repo.
enum VideoFixture {
    /// Writes a short H.264 .mp4 of mid-grey frames (brightness varies per
    /// frame) to a temporary location.
    static func makeMP4(
        seconds: Int = 2,
        fps: Int32 = 30,
        size: CGSize = CGSize(width: 320, height: 240)
    ) async throws -> URL {
        let url = temporaryURL(extension: "mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.writeFailed }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<(seconds * Int(fps)) {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            let buffer = try makeFrame(size: size, pool: adaptor.pixelBufferPool, shade: UInt8(128 + frame % 64))
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? FixtureError.writeFailed
            }
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? FixtureError.writeFailed }
        return url
    }

    /// Writes bytes that carry an .mp4 extension but aren't a valid movie.
    static func makeCorruptMP4() throws -> URL {
        let url = temporaryURL(extension: "mp4")
        try Data("this is not a movie".utf8).write(to: url)
        return url
    }

    private static func makeFrame(size: CGSize, pool: CVPixelBufferPool?, shade: UInt8) throws -> CVPixelBuffer {
        guard let pool else { throw FixtureError.writeFailed }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { throw FixtureError.writeFailed }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, Int32(shade), CVPixelBufferGetDataSize(buffer))
        }
        return buffer
    }

    private static func temporaryURL(extension ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("render-fixture-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    enum FixtureError: Error {
        case writeFailed
    }
}
