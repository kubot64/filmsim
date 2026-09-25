// Develop a DNG with CIRAWFilter and write linear Display P3 float32 RGB.
//
// Mirrors RawDeveloper.developLinear (ios/FilmSimCore) except two things: the shot
// orientation is kept (the output is upright) and there is no 35mm crop. Keep the
// filter settings in sync with RawDeveloper.
//
// Usage: ci_linear <in.DNG> <out.f32>
// Writes H*W*3 float32 (row-major, RGB) and prints one JSON line with the size and EXIF.
import CoreImage
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: ci_linear <in.DNG> <out.f32>\n".data(using: .utf8)!)
    exit(2)
}
let url = URL(fileURLWithPath: args[1])
let data = try Data(contentsOf: url)
guard let filter = CIRAWFilter(imageData: data, identifierHint: nil) else {
    FileHandle.standardError.write("CIRAWFilter could not open \(args[1])\n".data(using: .utf8)!)
    exit(1)
}
filter.boostAmount = 0
filter.boostShadowAmount = 0
filter.localToneMapAmount = 0
filter.isGamutMappingEnabled = true
filter.isLensCorrectionEnabled = true
filter.luminanceNoiseReductionAmount = 0.3
filter.colorNoiseReductionAmount = 0.5
filter.sharpnessAmount = 0
filter.scaleFactor = 1
filter.extendedDynamicRangeAmount = 0
guard let image = filter.outputImage else { exit(1) }

let rect = image.extent.integral
let w = Int(rect.width), h = Int(rect.height)
let space = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
let context = CIContext(options: [.workingColorSpace: space])
var rgba = [Float](repeating: 0, count: w * h * 4)
context.render(image, toBitmap: &rgba, rowBytes: w * 16, bounds: rect, format: .RGBAf, colorSpace: space)
var rgb = [Float](repeating: 0, count: w * h * 3)
for i in 0..<(w * h) {
    rgb[i * 3] = rgba[i * 4]
    rgb[i * 3 + 1] = rgba[i * 4 + 1]
    rgb[i * 3 + 2] = rgba[i * 4 + 2]
}
try rgb.withUnsafeBufferPointer { try Data(buffer: $0).write(to: URL(fileURLWithPath: args[2])) }

var exif: [String: Any] = [:]
if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
   let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
   let e = props[kCGImagePropertyExifDictionary as String] as? [String: Any] {
    exif["exposure_time"] = e[kCGImagePropertyExifExposureTime as String]
    exif["f_number"] = e[kCGImagePropertyExifFNumber as String]
    exif["iso"] = (e[kCGImagePropertyExifISOSpeedRatings as String] as? [Any])?.first
    exif["exposure_bias"] = e[kCGImagePropertyExifExposureBiasValue as String]
}
let info: [String: Any] = [
    "width": w, "height": h,
    "baseline_exposure": filter.baselineExposure,
    "exif": exif,
]
print(String(data: try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]), encoding: .utf8)!)
