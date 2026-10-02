import ImageIO
import UIKit
import XCTest
@testable import HaloField

final class HaloImagePipelineTests: XCTestCase {
    func testInvalidPhotoFailsWithoutCrashing() {
        XCTAssertThrowsError(
            try HaloImagePipeline.normalizedJPEG(fromEncodedData: Data([0x00, 0x01, 0x02]))
        )
    }

    func testEmptyPhotoFailsWithoutCrashing() {
        XCTAssertThrowsError(
            try HaloImagePipeline.normalizedJPEG(fromEncodedData: Data())
        )
    }

    func testLargePhotoIsDownsampledAndBounded() throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 3200, height: 2400)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3200, height: 2400))
            UIColor.white.setFill()
            context.fill(CGRect(x: 250, y: 250, width: 2700, height: 1900))
        }
        let sourceData = try XCTUnwrap(source.jpegData(compressionQuality: 0.98))
        let output = try HaloImagePipeline.normalizedJPEG(
            fromEncodedData: sourceData,
            maxPixelSize: 1200,
            maxBytes: 900_000
        )

        XCTAssertLessThanOrEqual(output.count, 900_000)

        let imageSource = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        XCTAssertLessThanOrEqual(max(width, height), 1200)
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
    }

    func testSourceSizeGuardRejectsUnreasonablePayloadBeforeDecode() {
        let oversized = Data(repeating: 0, count: HaloImagePipeline.maxSourceBytes + 1)
        XCTAssertThrowsError(try HaloImagePipeline.normalizedJPEG(fromEncodedData: oversized)) { error in
            XCTAssertEqual(error as? HaloImagePipelineError, .sourceTooLarge)
        }
    }
}
