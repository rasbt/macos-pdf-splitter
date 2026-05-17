import AppKit
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct OutputOptions {
    let pdf: Bool
    let png: Bool
    let webp: Bool
}

enum PDFProcessingError: LocalizedError {
    case invalidPDF
    case cancelled
    case webpUnavailable(String)
    case webpConversionFailed(String)
    case popplerUnavailable(String)
    case popplerRenderFailed(String)
    case imageDestinationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Could not open the PDF file."
        case .cancelled:
            return "Processing stopped."
        case .webpUnavailable(let message):
            return message
        case .webpConversionFailed(let message):
            return message
        case .popplerUnavailable(let message):
            return message
        case .popplerRenderFailed(let message):
            return message
        case .imageDestinationFailed(let message):
            return message
        }
    }
}

final class PDFProcessingCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

enum PDFProcessor {
    private enum ImageRenderer {
        case pdfKit
        case poppler(URL, PopplerTool)
    }

    private enum PopplerTool {
        case pdftocairo
        case pdftoppm
    }

    private enum WebpExportMode {
        case imageIO(UTType)
        case cwebp(URL)
    }

    static func process(
        pdfURL: URL,
        outputDirectory: URL,
        outputs: OutputOptions,
        dpi: Int,
        padding: Int,
        scalePercent: Int,
        webpQuality: Int,
        usePoppler: Bool,
        prefix: String?,
        shouldCancel: () -> Bool = { false },
        log: (String) -> Void
    ) throws {
        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFProcessingError.invalidPDF
        }

        try checkCancelled(shouldCancel)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let pageCount = document.pageCount
        let filenamePrefix = formatFilenamePrefix(prefix)
        let scaleFactor = max(0.1, Double(scalePercent) / 100.0)

        if outputs.pdf {
            for index in 0..<pageCount {
                try checkCancelled(shouldCancel)
                guard let page = document.page(at: index) else { continue }
                let pageDoc = PDFDocument()
                pageDoc.insert(page, at: 0)

                let filename = pageFilename(
                    filenamePrefix: filenamePrefix,
                    pageIndex: index,
                    fileExtension: "pdf"
                )
                let outputURL = outputDirectory.appendingPathComponent(filename)
                if pageDoc.write(to: outputURL) {
                    log("Saved page PDF: \(outputURL.path)")
                } else {
                    throw PDFProcessingError.imageDestinationFailed("Failed to write PDF: \(outputURL.path)")
                }
                try checkCancelled(shouldCancel)
            }
            log("Split into \(pageCount) single-page PDFs.")
        }

        let needsImages = outputs.png || outputs.webp
        if needsImages {
            try checkCancelled(shouldCancel)
            let renderer = try imageRenderer(usePoppler: usePoppler)
            let webpMode = try webpExportModeIfNeeded(outputs.webp)
            for index in 0..<pageCount {
                try checkCancelled(shouldCancel)
                let page = document.page(at: index)
                guard let rendered = try render(
                    page: page,
                    pageIndex: index,
                    pdfURL: pdfURL,
                    dpi: dpi,
                    renderer: renderer,
                    shouldCancel: shouldCancel
                ) else { continue }
                try checkCancelled(shouldCancel)
                let trimmed = trimWhitespace(image: rendered)
                try checkCancelled(shouldCancel)
                let padded = addPadding(image: trimmed, padding: max(0, padding))
                let resized = resize(image: padded, scale: scaleFactor)
                try checkCancelled(shouldCancel)

                let baseFilename = pageFilename(
                    filenamePrefix: filenamePrefix,
                    pageIndex: index,
                    fileExtension: nil
                )

                var pngURLForCwebp: URL?
                if outputs.png {
                    let pngURL = outputDirectory.appendingPathComponent("\(baseFilename).png")
                    try checkCancelled(shouldCancel)
                    try writeImage(resized, to: pngURL, type: .png, dpi: dpi)
                    log("Saved PNG (\(dpi) DPI): \(pngURL.path)")
                    pngURLForCwebp = pngURL
                }

                if outputs.webp {
                    try checkCancelled(shouldCancel)
                    let webpURL = outputDirectory.appendingPathComponent("\(baseFilename).webp")
                    guard let webpMode else {
                        throw PDFProcessingError.webpUnavailable("WEBP export is not supported on this system.")
                    }

                    switch webpMode {
                    case .imageIO(let webpType):
                        try writeImage(resized, to: webpURL, type: webpType, dpi: nil, quality: webpQuality)
                        log("Saved WEBP: \(webpURL.path)")
                    case .cwebp(let executableURL):
                        var tempURL: URL?
                        defer {
                            if let tempURL {
                                try? FileManager.default.removeItem(at: tempURL)
                            }
                        }
                        let inputURL: URL
                        if let pngURLForCwebp {
                            inputURL = pngURLForCwebp
                        } else {
                            let tmp = temporaryPNGURL(baseName: baseFilename)
                            try writeImage(resized, to: tmp, type: .png, dpi: dpi)
                            tempURL = tmp
                            inputURL = tmp
                        }

                        try runCwebp(
                            executable: executableURL,
                            inputURL: inputURL,
                            outputURL: webpURL,
                            quality: webpQuality,
                            shouldCancel: shouldCancel
                        )
                        log("Saved WEBP (cwebp): \(webpURL.path)")
                    }
                }
            }
        }
    }

    private static func checkCancelled(_ shouldCancel: () -> Bool) throws {
        if shouldCancel() {
            throw PDFProcessingError.cancelled
        }
    }

    private static func formatFilenamePrefix(_ prefix: String?) -> String {
        guard let prefix = prefix?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prefix.isEmpty else {
            return ""
        }
        return prefix
    }

    private static func pageFilename(
        filenamePrefix: String,
        pageIndex: Int,
        fileExtension: String?
    ) -> String {
        let pageString = String(format: "%02d", pageIndex + 1)
        let baseName: String
        if filenamePrefix.isEmpty {
            baseName = pageString
        } else {
            baseName = "\(filenamePrefix)F\(pageString)_raschka"
        }
        if let fileExtension = fileExtension {
            return "\(baseName).\(fileExtension)"
        }
        return baseName
    }

    private static func render(
        page: PDFPage?,
        pageIndex: Int,
        pdfURL: URL,
        dpi: Int,
        renderer: ImageRenderer,
        shouldCancel: () -> Bool
    ) throws -> CGImage? {
        try checkCancelled(shouldCancel)
        switch renderer {
        case .pdfKit:
            guard let page else { return nil }
            return renderPDFKit(page: page, dpi: dpi)
        case .poppler(let executable, let tool):
            return try renderPoppler(
                executable: executable,
                tool: tool,
                pdfURL: pdfURL,
                pageIndex: pageIndex,
                dpi: dpi,
                shouldCancel: shouldCancel
            )
        }
    }

    private static func renderPDFKit(page: PDFPage, dpi: Int) -> CGImage? {
        guard let pageRef = page.pageRef else { return nil }
        let pageRect = pageRef.getBoxRect(.mediaBox)
        let scale = CGFloat(dpi) / 72.0
        let width = max(1, Int(pageRect.width * scale))
        let height = max(1, Int(pageRect.height * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.saveGState()
        let targetRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let transform = pageRef.getDrawingTransform(.mediaBox, rect: targetRect, rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        context.drawPDFPage(pageRef)
        context.restoreGState()

        return context.makeImage()
    }

    private static func renderPoppler(
        executable: URL,
        tool: PopplerTool,
        pdfURL: URL,
        pageIndex: Int,
        dpi: Int,
        shouldCancel: () -> Bool
    ) throws -> CGImage? {
        try checkCancelled(shouldCancel)
        let pageNumber = pageIndex + 1
        let tempDir = FileManager.default.temporaryDirectory
        let baseName = "pdfsplitter_\(UUID().uuidString)"
        let baseURL = tempDir.appendingPathComponent(baseName)
        let outputURL = baseURL.appendingPathExtension("png")

        let arguments: [String]
        let candidates: [URL]
        switch tool {
        case .pdftocairo:
            arguments = [
                "-png",
                "-r", "\(dpi)",
                "-f", "\(pageNumber)",
                "-l", "\(pageNumber)",
                "-singlefile",
                pdfURL.path,
                baseURL.path
            ]
            candidates = [
                outputURL,
                tempDir.appendingPathComponent("\(baseName)-\(pageNumber)").appendingPathExtension("png")
            ]
        case .pdftoppm:
            arguments = [
                "-png",
                "-r", "\(dpi)",
                "-f", "\(pageNumber)",
                "-l", "\(pageNumber)",
                pdfURL.path,
                baseURL.path
            ]
            candidates = [
                tempDir.appendingPathComponent("\(baseName)-\(pageNumber)").appendingPathExtension("png"),
                tempDir.appendingPathComponent("\(baseName)-\(String(format: "%02d", pageNumber))")
                    .appendingPathExtension("png"),
                outputURL
            ]
        }
        defer {
            removePopplerOutputs(prefix: baseName, candidates: candidates, in: tempDir)
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw PDFProcessingError.popplerRenderFailed("Failed to launch poppler: \(error.localizedDescription)")
        }
        try waitForProcess(process, shouldCancel: shouldCancel)
        if process.terminationStatus != 0 {
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let message = ([stdout, stderr].joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            throw PDFProcessingError.popplerRenderFailed("Poppler failed: \(message)")
        }

        let imageURL = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
            ?? findPopplerOutput(prefix: baseName, in: tempDir)
        guard let imageURL else {
            throw PDFProcessingError.popplerRenderFailed("Poppler did not produce an output image.")
        }

        let imageData: Data
        do {
            imageData = try Data(contentsOf: imageURL)
        } catch {
            throw PDFProcessingError.popplerRenderFailed("Failed to read poppler output: \(error.localizedDescription)")
        }

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    private static func findPopplerOutput(prefix: String, in directory: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        return contents.first { url in
            url.pathExtension.lowercased() == "png" && url.lastPathComponent.hasPrefix(prefix)
        }
    }

    private static func removePopplerOutputs(prefix: String, candidates: [URL], in directory: URL) {
        for url in candidates {
            try? FileManager.default.removeItem(at: url)
        }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for url in contents where url.pathExtension.lowercased() == "png" && url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func trimWhitespace(image: CGImage, threshold: UInt8 = 245) -> CGImage {
        guard let data = image.dataProvider?.data else { return image }
        guard let ptr = CFDataGetBytePtr(data) else { return image }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false

        for y in 0..<height {
            let row = ptr + y * bytesPerRow
            for x in 0..<width {
                let pixel = row + x * bytesPerPixel
                let r = pixel[0]
                let g = bytesPerPixel > 1 ? pixel[1] : r
                let b = bytesPerPixel > 2 ? pixel[2] : r
                let a = bytesPerPixel > 3 ? pixel[3] : 255

                if a > 0 && (r < threshold || g < threshold || b < threshold) {
                    found = true
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                }
            }
        }

        guard found else { return image }
        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX + 1),
            height: max(1, maxY - minY + 1)
        )
        return image.cropping(to: cropRect) ?? image
    }

    private static func addPadding(image: CGImage, padding: Int) -> CGImage {
        guard padding > 0 else { return image }
        let newWidth = image.width + padding * 2
        let newHeight = image.height + padding * 2

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        let drawRect = CGRect(
            x: padding,
            y: padding,
            width: image.width,
            height: image.height
        )
        context.draw(image, in: drawRect)
        return context.makeImage() ?? image
    }

    private static func resize(image: CGImage, scale: Double) -> CGImage {
        guard abs(scale - 1.0) > 0.001 else { return image }
        let newWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let newHeight = max(1, Int((Double(image.height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }

    private static func imageRenderer(usePoppler: Bool) throws -> ImageRenderer {
        guard usePoppler else { return .pdfKit }
        if let pdftocairo = findExecutable(named: "pdftocairo") {
            return .poppler(pdftocairo, .pdftocairo)
        }
        if let pdftoppm = findExecutable(named: "pdftoppm") {
            return .poppler(pdftoppm, .pdftoppm)
        }
        throw PDFProcessingError.popplerUnavailable(
            "Poppler rendering is enabled but pdftocairo/pdftoppm was not found. Install poppler with `brew install poppler`."
        )
    }

    private static func writeImage(
        _ image: CGImage,
        to url: URL,
        type: UTType,
        dpi: Int?,
        quality: Int? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw PDFProcessingError.imageDestinationFailed("Failed to create image destination for \(type.identifier).")
        }

        var properties: [CFString: Any] = [:]
        if let dpi = dpi {
            properties[kCGImagePropertyDPIWidth] = dpi
            properties[kCGImagePropertyDPIHeight] = dpi
        }
        if type == .webP {
            let normalized: Double
            if let quality = quality {
                let clamped = max(1, min(100, quality))
                normalized = Double(clamped) / 100.0
            } else {
                normalized = 0.9
            }
            properties[kCGImageDestinationLossyCompressionQuality] = normalized
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        if !CGImageDestinationFinalize(destination) {
            throw PDFProcessingError.imageDestinationFailed("Failed to write image file.")
        }
    }

    private static func webpUTType() -> UTType? {
        guard #available(macOS 11.0, *) else {
            return nil
        }
        let supported = supportedImageDestinations()
        if let type = UTType(filenameExtension: "webp"),
           supported.contains(type.identifier) {
            return type
        }
        if let type = UTType("org.webmproject.webp"),
           supported.contains(type.identifier) {
            return type
        }
        return nil
    }

    private static func supportedImageDestinations() -> Set<String> {
        guard let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] else {
            return []
        }
        return Set(identifiers)
    }

    private static func webpExportModeIfNeeded(_ enabled: Bool) throws -> WebpExportMode? {
        guard enabled else { return nil }
        if #available(macOS 11.0, *), let type = webpUTType() {
            return .imageIO(type)
        }
        if let cwebpURL = findExecutable(named: "cwebp") {
            return .cwebp(cwebpURL)
        }
        if #available(macOS 11.0, *) {
            throw PDFProcessingError.webpUnavailable(
                "WEBP export is not supported by ImageIO on this system, and `cwebp` is not available. Install it with `brew install webp`."
            )
        }
        throw PDFProcessingError.webpUnavailable(
            "WEBP export requires macOS 11+ or `cwebp` from `brew install webp`."
        )
    }

    private static func findExecutable(named name: String) -> URL? {
        let envPaths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map { String($0) } ?? []
        let fallbackPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
        var searchPaths: [String] = []
        var seen = Set<String>()
        for entry in envPaths + fallbackPaths {
            if seen.contains(entry) { continue }
            seen.insert(entry)
            searchPaths.append(entry)
        }
        for entry in searchPaths {
            let url = URL(fileURLWithPath: entry).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func temporaryPNGURL(baseName: String) -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "\(baseName)_\(UUID().uuidString).png"
        return tempDir.appendingPathComponent(filename)
    }

    private static func runCwebp(
        executable: URL,
        inputURL: URL,
        outputURL: URL,
        quality: Int,
        shouldCancel: () -> Bool
    ) throws {
        try checkCancelled(shouldCancel)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-q", "\(quality)", inputURL.path, "-o", outputURL.path]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
        } catch {
            throw PDFProcessingError.webpConversionFailed("Failed to launch cwebp: \(error.localizedDescription)")
        }
        do {
            try waitForProcess(process, shouldCancel: shouldCancel)
        } catch {
            if case PDFProcessingError.cancelled = error {
                try? FileManager.default.removeItem(at: outputURL)
            }
            throw error
        }
        if process.terminationStatus != 0 {
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            let message = ([stdout, stderr].joined(separator: "\n")).trimmingCharacters(in: .whitespacesAndNewlines)
            throw PDFProcessingError.webpConversionFailed("cwebp failed: \(message)")
        }
    }

    private static func waitForProcess(
        _ process: Process,
        shouldCancel: () -> Bool
    ) throws {
        while process.isRunning {
            if shouldCancel() {
                process.terminate()
                process.waitUntilExit()
                throw PDFProcessingError.cancelled
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
