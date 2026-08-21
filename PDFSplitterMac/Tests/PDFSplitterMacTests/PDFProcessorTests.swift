import AppKit
import XCTest
@testable import PDFSplitterMac

final class PDFProcessorTests: XCTestCase {
    func testBorderHonorsEnabledColorAndPixelWidth() throws {
        let source = try XCTUnwrap(makeWhiteImage(width: 12, height: 12))
        let disabled = BorderOptions(
            enabled: false,
            red: 0,
            green: 0,
            blue: 0,
            alpha: 1,
            lineWidth: 3
        )
        let disabledResult = PDFProcessor.addBorder(image: source, options: disabled)
        assertColor(try color(in: disabledResult, x: 0, y: 6), red: 1, green: 1, blue: 1)

        let enabled = BorderOptions(
            enabled: true,
            red: 1,
            green: 0,
            blue: 0,
            alpha: 1,
            lineWidth: 3
        )
        let enabledResult = PDFProcessor.addBorder(image: source, options: enabled)

        assertColor(try color(in: enabledResult, x: 0, y: 6), red: 1, green: 0, blue: 0)
        assertColor(try color(in: enabledResult, x: 2, y: 6), red: 1, green: 0, blue: 0)
        assertColor(try color(in: enabledResult, x: 3, y: 6), red: 1, green: 1, blue: 1)
    }

    func testDisablingCropPreservesFullRenderedPage() throws {
        let source = try XCTUnwrap(
            makeWhiteImage(
                width: 12,
                height: 12,
                contentRect: CGRect(x: 4, y: 3, width: 3, height: 5)
            )
        )

        let uncropped = PDFProcessor.cropWhitespaceIfEnabled(image: source, enabled: false)
        XCTAssertEqual(uncropped.width, 12)
        XCTAssertEqual(uncropped.height, 12)

        let cropped = PDFProcessor.cropWhitespaceIfEnabled(image: source, enabled: true)
        XCTAssertEqual(cropped.width, 3)
        XCTAssertEqual(cropped.height, 5)
    }

    private func makeWhiteImage(
        width: Int,
        height: Int,
        contentRect: CGRect? = nil
    ) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let contentRect {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(contentRect)
        }
        return context.makeImage()
    }

    private func color(in image: CGImage, x: Int, y: Int) throws -> NSColor {
        let bitmap = NSBitmapImageRep(cgImage: image)
        let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y))
        return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
    }

    private func assertColor(
        _ color: NSColor,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(color.redComponent, red, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(color.greenComponent, green, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(color.blueComponent, blue, accuracy: 0.01, file: file, line: line)
    }
}
