import CoreImage
import CoreImage.CIFilterBuiltins

/// Film grain: luminance-weighted monochrome noise, mirroring research/filmsim/grain.py.
public enum Grain {
    static func amplitude(_ s: GrainStrength) -> Double {
        switch s { case .off: return 0; case .weak: return 0.025; case .strong: return 0.05 }
    }
    static func sigma(_ s: GrainSize) -> Double {
        switch s { case .small: return 0.6; case .large: return 1.1 }
    }

    public static func apply(to image: CIImage, strength: GrainStrength, size: GrainSize) -> CIImage {
        let amp = amplitude(strength)
        if amp == 0 { return image }
        // TODO: match the Python weighting sqrt(L)*(1-L)*2 with a custom kernel.
        // Placeholder: blurred random noise, soft-light blended.
        let noise = CIFilter.randomGenerator().outputImage!
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0),
            ])
            .applyingGaussianBlur(sigma: sigma(size))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: amp * 4, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: amp * 4, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: amp * 4, w: 0),
                "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 1),
            ])
            .cropped(to: image.extent)
        return noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }
}
