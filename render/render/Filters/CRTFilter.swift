//
//  CRTFilter.swift
//  render
//

import CoreImage
import CoreImage.CIFilterBuiltins
import os

/// Recreates the look of a 90s CRT: curved glass, scanlines, an aperture
/// grille, convergence error, glow, noise and flicker.
nonisolated struct CRTFilter: VideoFilter {
    var settings: CRTSettings

    /// Whether the CRT kernel compiled on this Mac. When it didn't, the
    /// filter passes frames through untouched rather than failing playback.
    static var isAvailable: Bool { kernel != nil }

    func apply(to image: CIImage, time: Double) -> CIImage {
        guard let kernel = Self.kernel else { return image }

        let extent = image.extent
        let scale = extent.height / 1080
        let aberration = settings.aberration * scale

        var input = image.clampedToExtent()
        if settings.softness > 0 {
            input = input.applyingGaussianBlur(sigma: settings.softness * scale)
        }

        // Curvature can pull a pixel from up to `curvature` of the frame
        // away, and convergence error from `aberration` pixels sideways.
        let reachX = settings.curvature * extent.width + aberration + 1
        let reachY = settings.curvature * extent.height + 1
        let crt = kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -reachX, dy: -reachY) },
            arguments: [
                input,
                CIVector(cgRect: extent),
                settings.curvature,
                settings.scanlineIntensity,
                settings.scanlineCount,
                settings.maskIntensity,
                aberration,
                settings.vignette,
                settings.noise,
                settings.flicker,
                settings.brightness,
                time,
            ]
        )
        guard var output = crt else { return image }

        if settings.bloom > 0 {
            let bloom = CIFilter.bloom()
            bloom.inputImage = output
            bloom.radius = Float(12 * scale)
            bloom.intensity = Float(settings.bloom)
            output = bloom.outputImage ?? output
        }

        if settings.saturation != 1 {
            let color = CIFilter.colorControls()
            color.inputImage = output
            color.saturation = Float(settings.saturation)
            output = color.outputImage ?? output
        }

        return output.cropped(to: extent)
    }

    // MARK: - Kernel

    /// Compiled once at runtime from Metal source, so building the app
    /// doesn't need Xcode's separately downloaded Metal toolchain.
    private static let kernel: CIKernel? = {
        do {
            return try CIKernel.kernels(withMetalString: kernelSource).first
        } catch {
            Logger(subsystem: "kavi.render", category: "filters")
                .error("CRT kernel failed to compile: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

    private static let kernelSource = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    /// Cheap per-pixel pseudo random number in [0, 1).
    static float crtHash(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    }

    /// `extent` is the frame rect (x, y, width, height) in pixels.
    [[stitchable]] float4 crt(coreimage::sampler src,
                              float4 extent,
                              float curvature,
                              float scanlineIntensity,
                              float scanlineCount,
                              float maskIntensity,
                              float aberration,
                              float vignette,
                              float noise,
                              float flicker,
                              float brightness,
                              float time,
                              coreimage::destination dest)
    {
        float2 coord = dest.coord();
        float2 uv = (coord - extent.xy) / extent.zw;

        // Barrel distortion: sample further out with distance from the
        // centre so the picture bulges like the face of a tube.
        float2 centered = uv * 2.0 - 1.0;
        centered *= 1.0 + curvature * dot(centered, centered);
        uv = centered * 0.5 + 0.5;

        // Beyond the curved glass is black, with a soft edge.
        float edge = 0.004 + curvature * 0.02;
        float2 inside = smoothstep(0.0, edge, uv) * smoothstep(0.0, edge, 1.0 - uv);
        float screen = inside.x * inside.y;
        if (screen <= 0.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }

        // Convergence error: red and blue land off green, worse at the edges.
        float2 position = uv * extent.zw + extent.xy;
        float2 shift = float2(aberration * (0.5 + 0.5 * length(centered)), 0.0);
        float4 green = src.sample(src.transform(position));
        float red = src.sample(src.transform(position + shift)).r;
        float blue = src.sample(src.transform(position - shift)).b;
        float3 color = float3(red, green.g, blue);

        // Scanlines: sin^2 bands, `scanlineCount` lines top to bottom.
        float band = sin(uv.y * scanlineCount * M_PI_F);
        color *= 1.0 - scanlineIntensity * (1.0 - band * band);

        // Aperture grille: vertical R/G/B phosphor stripes, 3 px per triad.
        int stripe = int(fmod(floor(coord.x), 3.0));
        float3 mask = float3(1.0 - maskIntensity);
        mask[stripe] = 1.0;
        color *= mask;

        // Vignette towards the corners of the tube.
        float corners = uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
        color *= pow(clamp(16.0 * corners, 0.0, 1.0), vignette * 0.35);

        // Tube noise and per-frame brightness flicker.
        color += (crtHash(coord + fract(time) * 517.0) - 0.5) * noise;
        color *= 1.0 - flicker * crtHash(float2(time, time * 0.37));

        color *= brightness * screen;
        return float4(clamp(color, 0.0, 1.0), green.a);
    }
    """
}
