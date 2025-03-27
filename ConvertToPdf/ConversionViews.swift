import SwiftUI
import PDFKit
import Cocoa
import AppKit
import Foundation
import UniformTypeIdentifiers

// Dönüştürme işlemi esnasında görüntülenen ilerleme ekranı
struct ConversionProgressView: View {
    var progress: Double
    
    var body: some View {
        VStack(spacing: 10) {
            Text("Dönüştürülüyor...")
                .font(.headline)
            
            ProgressView(value: progress)
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 200)
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.windowBackgroundColor))
                .shadow(radius: 5)
        )
    }
}

// Dosya seçme ve kaydetme işlemleri için view model
class FileSelectionViewModel: ObservableObject {
    @Published var selectedFile: URL?
    @Published var showFilePicker = false
    
    func selectFile(fileTypes: [String]) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if !fileTypes.isEmpty {
            panel.allowedContentTypes = fileTypes.compactMap { UTType(filenameExtension: $0) }
        }
        
        if panel.runModal() == .OK {
            self.selectedFile = panel.url
        }
    }
    
    func saveFile(defaultFilename: String, fileType: String, completion: @escaping (URL?) -> Void) {
        let savePanel = NSSavePanel()
        if let contentType = UTType(filenameExtension: fileType) {
            savePanel.allowedContentTypes = [contentType]
        }
        savePanel.nameFieldStringValue = defaultFilename
        
        if savePanel.runModal() == .OK {
            completion(savePanel.url)
        } else {
            completion(nil)
        }
    }
}

// Dönüştürme işlemi için view model
class ConversionViewModel: ObservableObject {
    @Published var isConverting = false
    @Published var conversionProgress: Double = 0.0
    @Published var showError = false
    @Published var errorMessage: String?
    @Published var showConversionSuccess = false
    @Published var convertedFileURL: URL?
    
    // Hata mesajı göster
    func showError(_ message: String) {
        self.errorMessage = message
        self.showError = true
        self.isConverting = false
    }
    
    // Dosya dönüştürme işlemi
    func convertFile(inputURL: URL, outputFormat: String, completion: @escaping (Bool, URL?) -> Void) {
        guard !isConverting else { return }
        
        let inputFormat = inputURL.pathExtension.lowercased()
        let conversionType = FileConverter.determineConversionType(inputFormat: inputFormat, outputFormat: outputFormat)
        
        if conversionType == .Unknown {
            print("❌ Desteklenmeyen dönüşüm: \(inputFormat) -> \(outputFormat)")
            self.showError("Bu dönüşüm tipi desteklenmiyor: \(inputFormat) -> \(outputFormat)")
            return
        }
        
        // Kaydedilecek dosya yolunu belirle
        let savePanel = NSSavePanel()
        if let contentType = UTType(filenameExtension: outputFormat) {
            savePanel.allowedContentTypes = [contentType]
        }
        // Dosya adını orijinal isim olarak ayarla, uzantısını değiştir
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "." + outputFormat
        
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else {
            return
        }
        
        isConverting = true
        conversionProgress = 0.0
        
        // Dönüşümü başlat
        let progressUpdate: (Double) -> Void = { [weak self] progress in
            DispatchQueue.main.async {
                self?.conversionProgress = progress
            }
        }
        
        // Doğru dönüşüm fonksiyonunu çağır
        switch conversionType {
        case .PDFToJPEG, .PDFToJPG:
            FileConverter.convertPDFToJPEG(pdfURL: inputURL, saveURL: saveURL, progressUpdate: progressUpdate) { success, outputURL in
                DispatchQueue.main.async {
                    self.finishConversion(success: success, outputURL: outputURL, completion: completion)
                }
            }
        case .PDFToPNG:
            FileConverter.convertPDFToPNG(pdfURL: inputURL, saveURL: saveURL, progressUpdate: progressUpdate) { success, outputURL in
                DispatchQueue.main.async {
                    self.finishConversion(success: success, outputURL: outputURL, completion: completion)
                }
            }
        case .PDFToPDF:
            FileConverter.convertPDFToPDF(pdfURL: inputURL, saveURL: saveURL) { success, outputURL in
                DispatchQueue.main.async {
                    self.finishConversion(success: success, outputURL: outputURL, completion: completion)
                }
            }
        case .ImageToPDF:
            FileConverter.convertImageToPDF(imageURL: inputURL, saveURL: saveURL) { success, outputURL in
                DispatchQueue.main.async {
                    self.finishConversion(success: success, outputURL: outputURL, completion: completion)
                }
            }
        case .OfficeToPDF:
            FileConverter.convertWithLibreOffice(fileURL: inputURL, saveURL: saveURL) { success, outputURL in
                DispatchQueue.main.async {
                    self.finishConversion(success: success, outputURL: outputURL, completion: completion)
                }
            }
        default:
            isConverting = false
            self.showError("Bu dönüşüm şu anda desteklenmiyor")
            completion(false, nil)
        }
    }
    
    private func finishConversion(success: Bool, outputURL: URL?, completion: @escaping (Bool, URL?) -> Void) {
        self.isConverting = false
        
        if success, let resultURL = outputURL {
            self.convertedFileURL = resultURL
            self.conversionProgress = 1.0
            self.showConversionSuccess = true
            completion(true, resultURL)
        } else {
            self.showError("Dönüştürme işlemi başarısız oldu")
            completion(false, nil)
        }
    }
}
