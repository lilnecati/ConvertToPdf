//
//  ContentView.swift
//  ConvertTo
//
//  Created by Necati Yıldırım on 27.03.2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedFileURL: URL?
    @State private var conversionResult: String = ""
    @State private var isProcessing: Bool = false
    @State private var selectedConversion: String = "PDF to Excel"

    let conversionOptions = [
        "PDF to Excel",
        "Excel to PDF",
        "PPTX to PDF",
        "PDF to PPTX",
        "DOCX to PDF",
        "PDF to DOCX"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text("File Converter")
                .font(.largeTitle)
                .bold()

            Button("Select File") {
                selectFile()
            }
            .buttonStyle(.borderedProminent)

            if let fileURL = selectedFileURL {
                Text("Selected File: \(fileURL.lastPathComponent)")
                    .font(.subheadline)
            }

            Picker("Conversion Type", selection: $selectedConversion) {
                ForEach(conversionOptions, id: \.self) { option in
                    Text(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .padding()

            Button("Convert") {
                convertFile()
            }
            .buttonStyle(.bordered)
            .disabled(selectedFileURL == nil || isProcessing)

            if isProcessing {
                ProgressView("Processing...")
            }

            Text(conversionResult)
                .font(.body)
                .foregroundColor(.green)
        }
        .padding()
    }

    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType.pdf,
            UTType(filenameExtension: "xlsx")!,
            UTType(filenameExtension: "pptx")!,
            UTType(filenameExtension: "docx")!
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            selectedFileURL = panel.url
        }
    }

    func convertFile() {
        guard let fileURL = selectedFileURL else { return }
        isProcessing = true
        conversionResult = "Processing..."

        // Simulate conversion (replace this with actual conversion logic)
        DispatchQueue.global().async {
            // Example: Add your conversion logic here
            // For now, we just simulate a delay
            sleep(2)

            DispatchQueue.main.async {
                isProcessing = false
                conversionResult = "Conversion completed: \(selectedConversion)"
            }
        }
    }
}

#Preview {
    ContentView()
}
