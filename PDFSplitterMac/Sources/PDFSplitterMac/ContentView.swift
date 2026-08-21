import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var pdfURL: URL?
    @State private var outputDirectory: URL?
    @State private var dpiText = "200"
    @State private var paddingText = "20"
    @State private var scaleText = "100"
    @State private var prefixText = "PrefixText_"
    @State private var cropWhitespace = true
    @State private var useBorder = false
    @State private var borderColor = Color.black
    @State private var borderLineWidthText = "3"
    @State private var outputPDF = true
    @State private var outputPNG = true
    @State private var outputWEBP = false
    @State private var webpQualityText = "90"
    @State private var usePoppler = true
    @State private var isProcessing = false
    @State private var isStopping = false
    @State private var processingCancellation: PDFProcessingCancellation?
    @State private var isDropTargeted = false
    @State private var logLines: [String] = ["Drop a PDF or choose a file."]
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PDF Splitter")
                .font(.system(size: 20, weight: .bold))

            dropArea

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledRow(label: "PDF:") {
                        Text(pdfURL?.lastPathComponent ?? "None")
                            .foregroundColor(pdfURL == nil ? .secondary : .primary)
                            .lineLimit(1)
                    }

                    LabeledRow(label: "Output:") {
                        Text(outputDirectory?.path ?? "None")
                            .foregroundColor(outputDirectory == nil ? .secondary : .primary)
                            .lineLimit(1)
                    }

                    LabeledRow(label: "Outputs:") {
                        HStack(spacing: 12) {
                            Toggle("PDF", isOn: $outputPDF)
                            Toggle("PNG", isOn: $outputPNG)
                            Toggle("WEBP", isOn: $outputWEBP)
                        }
                        .toggleStyle(.checkbox)
                    }

                    LabeledRow(label: "Crop:") {
                        Toggle("Whitespace", isOn: $cropWhitespace)
                            .toggleStyle(.checkbox)
                    }

                    LabeledRow(label: "Border:") {
                        HStack(spacing: 12) {
                            Toggle("Use", isOn: $useBorder)
                                .toggleStyle(.checkbox)
                            CompactColorWell(color: $borderColor)
                                .frame(width: 16, height: 16)
                                .clipped()
                                .disabled(!useBorder)
                            TextField("Width", text: $borderLineWidthText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 56)
                                .disabled(!useBorder)
                            Text("px")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    LabeledRow(label: "DPI:") {
                        TextField("", text: $dpiText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    LabeledRow(label: "Padding:") {
                        TextField("", text: $paddingText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    LabeledRow(label: "Scale %:") {
                        TextField("", text: $scaleText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }

                    LabeledRow(label: "Render:") {
                        Toggle("Poppler", isOn: $usePoppler)
                            .toggleStyle(.checkbox)
                    }

                    LabeledRow(label: "Prefix:") {
                        TextField("Optional", text: $prefixText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }

                    LabeledRow(label: "WEBP Q:") {
                        TextField("1-100", text: $webpQualityText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Choose PDF") {
                    choosePDF()
                }
                Button("Choose Output") {
                    chooseOutputFolder()
                }
                Button("Run") {
                    startProcessing()
                }
                .disabled(isProcessing)

                if isProcessing {
                    Button(isStopping ? "Stopping..." : "Stop") {
                        stopProcessing()
                    }
                    .disabled(isStopping)
                }

                Button("Open Output") {
                    openOutputFolder()
                }
                .disabled(outputDirectory == nil)

                if isProcessing {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }

            logArea
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .alert("Error", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isDropTargeted ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
                )

            VStack(spacing: 6) {
                Text("Drop a PDF here")
                    .font(.headline)
                Text("or click to choose")
                    .foregroundColor(.secondary)
            }
        }
        .frame(height: 140)
        .onTapGesture {
            choosePDF()
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private var logArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.05))
            .cornerRadius(8)
        }
    }

    private func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            setPDF(url)
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectory = url
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            DispatchQueue.main.async {
                setPDF(url)
            }
        }
        return true
    }

    private func setPDF(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else {
            showError("Please choose a PDF file.")
            return
        }
        pdfURL = url
        let baseName = url.deletingPathExtension().lastPathComponent
        outputDirectory = url.deletingLastPathComponent().appendingPathComponent("\(baseName)_output")
        appendLog("Selected PDF: \(url.lastPathComponent)")
    }

    private func openOutputFolder() {
        guard let outputDirectory = outputDirectory else { return }
        NSWorkspace.shared.open(outputDirectory)
    }

    private func startProcessing() {
        guard let pdfURL = pdfURL else {
            showError("Choose a PDF to process.")
            return
        }
        guard let outputDirectory = outputDirectory else {
            showError("Choose an output directory.")
            return
        }

        guard let dpi = Int(dpiText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let padding = Int(paddingText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            showError("DPI and padding must be whole numbers.")
            return
        }
        guard let scalePercent = Int(scaleText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (10...400).contains(scalePercent) else {
            showError("Scale must be between 10 and 400.")
            return
        }
        if dpi <= 0 {
            showError("DPI must be greater than 0.")
            return
        }
        if padding < 0 {
            showError("Padding must be 0 or greater.")
            return
        }

        let outputs = OutputOptions(pdf: outputPDF, png: outputPNG, webp: outputWEBP)
        if !outputs.pdf && !outputs.png && !outputs.webp {
            showError("Choose at least one output type.")
            return
        }
        var webpQuality = 90
        if outputs.webp {
            guard let parsed = Int(webpQualityText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...100).contains(parsed) else {
                showError("WEBP quality must be between 1 and 100.")
                return
            }
            webpQuality = parsed
        }
        var borderLineWidth = 3
        if useBorder {
            guard let parsed = Int(borderLineWidthText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  parsed > 0 else {
                showError("Border width must be a whole number greater than 0.")
                return
            }
            borderLineWidth = parsed
        }

        let resolvedBorderColor = NSColor(borderColor).usingColorSpace(.deviceRGB) ?? .black
        let borderOptions = BorderOptions(
            enabled: useBorder,
            red: Double(resolvedBorderColor.redComponent),
            green: Double(resolvedBorderColor.greenComponent),
            blue: Double(resolvedBorderColor.blueComponent),
            alpha: Double(resolvedBorderColor.alphaComponent),
            lineWidth: borderLineWidth
        )

        isProcessing = true
        isStopping = false
        appendLog("Starting processing...")
        let prefix = prefixText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixValue = prefix.isEmpty ? nil : prefix
        let usePopplerValue = usePoppler
        let cropWhitespaceValue = cropWhitespace
        let webpQualityValue = webpQuality
        let cancellation = PDFProcessingCancellation()
        processingCancellation = cancellation

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PDFProcessor.process(
                    pdfURL: pdfURL,
                    outputDirectory: outputDirectory,
                    outputs: outputs,
                    dpi: dpi,
                    padding: padding,
                    scalePercent: scalePercent,
                    webpQuality: webpQualityValue,
                    usePoppler: usePopplerValue,
                    cropWhitespace: cropWhitespaceValue,
                    prefix: prefixValue,
                    border: borderOptions,
                    shouldCancel: {
                        cancellation.isCancelled
                    },
                    log: { message in
                        appendLogFromBackground(message)
                    }
                )
                DispatchQueue.main.async {
                    isProcessing = false
                    isStopping = false
                    processingCancellation = nil
                    appendLog("Done.")
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    isStopping = false
                    processingCancellation = nil
                    if case PDFProcessingError.cancelled = error {
                        appendLog("Stopped.")
                    } else {
                        showError(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func stopProcessing() {
        guard let processingCancellation else { return }
        isStopping = true
        processingCancellation.cancel()
        appendLog("Stopping processing...")
    }

    private func appendLog(_ message: String) {
        logLines.append(message)
    }

    nonisolated private func appendLogFromBackground(_ message: String) {
        DispatchQueue.main.async {
            logLines.append(message)
        }
    }

    private func showError(_ message: String) {
        alertMessage = message
        showingAlert = true
        appendLog("Error: \(message)")
    }
}

private struct LabeledRow<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 70, alignment: .leading)
                .foregroundColor(.secondary)
            content
        }
    }
}

private struct CompactColorWell: NSViewRepresentable {
    @Binding var color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator {
        Coordinator(color: $color)
    }

    func makeNSView(context: Context) -> SquareColorWell {
        let colorWell = SquareColorWell()
        if #available(macOS 13.0, *) {
            colorWell.colorWellStyle = .minimal
        }
        colorWell.color = NSColor(color)
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }

    func updateNSView(_ colorWell: SquareColorWell, context: Context) {
        colorWell.color = NSColor(color)
        colorWell.isEnabled = isEnabled
    }

    @MainActor
    final class Coordinator: NSObject {
        private var color: Binding<Color>

        init(color: Binding<Color>) {
            self.color = color
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            color.wrappedValue = Color(nsColor: sender.color)
        }
    }
}

@MainActor
private final class SquareColorWell: NSColorWell {
    override var intrinsicContentSize: NSSize {
        NSSize(width: 16, height: 16)
    }
}
