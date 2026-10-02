import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum HaloImagePipelineError: LocalizedError {
    case emptyData
    case sourceTooLarge
    case unreadableImage
    case thumbnailFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .emptyData: "The selected photo is empty."
        case .sourceTooLarge: "This photo is too large to process safely. Choose a smaller image."
        case .unreadableImage: "HALO could not read this photo."
        case .thumbnailFailed: "HALO could not prepare this photo."
        case .encodingFailed: "HALO could not safely encode this photo."
        }
    }
}

enum HaloImagePipeline {
    static let maxSourceBytes = 80 * 1024 * 1024
    static let maxPixelSize = 2560
    static let maxUploadBytes = 3_500_000

    static func normalizedJPEG(
        fromEncodedData data: Data,
        maxPixelSize: Int = maxPixelSize,
        maxBytes: Int = maxUploadBytes
    ) throws -> Data {
        guard !data.isEmpty else { throw HaloImagePipelineError.emptyData }
        guard data.count <= maxSourceBytes else { throw HaloImagePipelineError.sourceTooLarge }

        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw HaloImagePipelineError.unreadableImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw HaloImagePipelineError.thumbnailFailed
        }

        var smallest: Data?
        for quality in [0.82, 0.72, 0.62, 0.52, 0.42, 0.34] {
            let encoded = try encodeJPEG(thumbnail, quality: quality)
            smallest = encoded
            if encoded.count <= maxBytes { return encoded }
        }

        guard let smallest, smallest.count <= maxBytes else {
            if maxPixelSize > 1600 {
                let intermediate = try encodeJPEG(thumbnail, quality: 0.40)
                return try normalizedJPEG(
                    fromEncodedData: intermediate,
                    maxPixelSize: 1600,
                    maxBytes: maxBytes
                )
            }
            throw HaloImagePipelineError.encodingFailed
        }
        return smallest
    }

    static func normalizedJPEG(
        from image: UIImage,
        maxPixelSize: Int = maxPixelSize,
        maxBytes: Int = maxUploadBytes
    ) throws -> Data {
        guard let seed = image.jpegData(compressionQuality: 0.82) else {
            throw HaloImagePipelineError.encodingFailed
        }
        return try normalizedJPEG(
            fromEncodedData: seed,
            maxPixelSize: maxPixelSize,
            maxBytes: maxBytes
        )
    }

    static func displayImage(fromEncodedData data: Data) throws -> UIImage {
        let normalized = try normalizedJPEG(fromEncodedData: data)
        guard let image = UIImage(data: normalized, scale: UIScreen.main.scale) else {
            throw HaloImagePipelineError.unreadableImage
        }
        return image
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw HaloImagePipelineError.encodingFailed
        }

        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )

        guard CGImageDestinationFinalize(destination) else {
            throw HaloImagePipelineError.encodingFailed
        }
        return output as Data
    }
}
