import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var pdfURL: URL?
    @State private var outputDirectory: URL?
    @State private var dpiText = "200"
    @State private var paddingText = "20"
    @State private var scaleText = "100"
    @State private var chapterText = ""
    @State private var outputPDF = true
    @State private var outputPNG = true
    @State private var outputWEBP = false
    @State private var webpQualityText = "90"
    @State private var usePoppler = true
    @State private var isProcessing = false
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

                    LabeledRow(label: "Chapter:") {
                        TextField("Optional", text: $chapterText)
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

        isProcessing = true
        appendLog("Starting processing...")
        let chapter = chapterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let chapterValue = chapter.isEmpty ? nil : chapter

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PDFProcessor.process(
                    pdfURL: pdfURL,
                    outputDirectory: outputDirectory,
                    outputs: outputs,
                    dpi: dpi,
                    padding: padding,
                    scalePercent: scalePercent,
                    webpQuality: webpQuality,
                    usePoppler: usePoppler,
                    chapter: chapterValue,
                    log: { message in
                        appendLogFromBackground(message)
                    }
                )
                DispatchQueue.main.async {
                    isProcessing = false
                    appendLog("Done.")
                }
            } catch {
                DispatchQueue.main.async {
                    isProcessing = false
                    showError(error.localizedDescription)
                }
            }
        }
    }

    private func appendLog(_ message: String) {
        logLines.append(message)
    }

    private func appendLogFromBackground(_ message: String) {
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
