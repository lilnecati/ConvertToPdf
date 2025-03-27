import SwiftUI
import PDFKit
import Cocoa
import AppKit
import Foundation

struct ContentView: View {
    @State private var selectedFileURL: URL?
    @State private var convertedFileURL: URL?
    @State private var isConverting = false
    
    var body: some View {
        VStack {
            Text("Dosya Dönüştürücü")
                .font(.largeTitle)
                .padding()
            
            // Dosya seçme butonu
            Button("Dosya Seç") {
                selectFile()
            }
            .padding()
            
            // Seçilen dosya yolunu göster
            if let selectedFileURL = selectedFileURL {
                Text("Seçilen Dosya: \(selectedFileURL.path)")
                    .padding()
                
                // Dönüştürme butonu
                Button("Dönüştür") {
                    convertFile(selectedFileURL)
                }
                .disabled(isConverting)
                .padding()
            }
            
            // Dönüştürülmüş dosya yolunu göster
            if let convertedFileURL = convertedFileURL {
                Text("Dönüştürülen Dosya: \(convertedFileURL.path)")
                    .foregroundColor(.green)
                    .padding()
            }
        }
        .frame(width: 400, height: 300)
    }
    
    // Dosya seçme işlemi
    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["pdf", "docx", "xlsx", "pptx", "jpg", "png"]
        if panel.runModal() == .OK {
            selectedFileURL = panel.url
        }
    }
    
    // Seçilen dosyayı dönüştürme işlemi
    func convertFile(_ fileURL: URL) {
        isConverting = true
        
        let fileExtension = fileURL.pathExtension.lowercased()
        let savePanel = NSSavePanel()
        
        switch fileExtension {
        case "pdf":
            // PDF'yi PNG'ye dönüştür
            savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent).png"
            savePanel.allowedFileTypes = ["png"]
            savePanel.begin { result in
                if result == .OK, let saveURL = savePanel.url {
                    convertPDFToPNG(pdfURL: fileURL, saveURL: saveURL)
                }
            }
        case "jpg", "png":
            // JPG veya PNG'yi PDF'ye dönüştür
            savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent).pdf"
            savePanel.allowedFileTypes = ["pdf"]
            savePanel.begin { result in
                if result == .OK, let saveURL = savePanel.url {
                    convertImageToPDF(imageURL: fileURL, saveURL: saveURL)
                }
            }
        case "docx", "xlsx", "pptx":
            // Office dosyasını PDF'ye dönüştür
            savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent).pdf"
            savePanel.allowedFileTypes = ["pdf"]
            savePanel.begin { result in
                if result == .OK, let saveURL = savePanel.url {
                    convertOfficeToPDF(officeURL: fileURL, saveURL: saveURL)
                }
            }
        default:
            print("Desteklenmeyen dosya türü.")
        }
    }
    
    // PDF'yi PNG'ye dönüştürme işlemi
    func convertPDFToPNG(pdfURL: URL, saveURL: URL) {
        guard let pdfDocument = PDFDocument(url: pdfURL), let page = pdfDocument.page(at: 0) else {
            print("Hata: PDF dosyası açılamadı veya sayfa bulunamadı.")
            return
        }
        
        // Sayfayı thumbnail olarak alıyoruz
        let image = page.thumbnail(of: CGSize(width: 1000, height: 1000), for: .mediaBox)
        
        // NSImage'yi PNG'ye dönüştürme işlemi
        if let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!) {
            guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                print("Hata: PNG verisi oluşturulamadı.")
                return
            }
            
            do {
                try pngData.write(to: saveURL)
                convertedFileURL = saveURL
                print("Dosya başarıyla kaydedildi: \(saveURL.path)")
            } catch {
                print("Hata: \(error.localizedDescription)")
            }
        } else {
            print("Hata: Bitmap image representation oluşturulamadı.")
        }
    }
    
    // JPG veya PNG'yi PDF'ye dönüştürme işlemi
    func convertImageToPDF(imageURL: URL, saveURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else {
            print("Hata: Görsel açılamadı.")
            return
        }
        
        // PDF dosyasına yazmak için NSData nesnesi
        let pdfData = NSMutableData()
        
        // PDFContext ile görseli PDF'ye çiziyoruz
        guard let pdfConsumer = CGDataConsumer(data: pdfData) else {
            print("Hata: PDF verisi için Consumer oluşturulamadı.")
            return
        }
        
        // Görseli çizmek için CGContext oluşturuluyor
        guard let pdfContext = CGContext(pdfConsumer, mediaBox: nil, nil) else {
            print("Hata: PDF context oluşturulamadı.")
            return
        }
        
        // PDF'ye sayfa ekliyoruz
        pdfContext.beginPage(mediaBox: nil)
        
        // Görseli PDF sayfasına çiziyoruz
        image.draw(at: CGPoint(x: 0, y: 0))
        
        pdfContext.endPage()
        
        // PDF'yi kaydediyoruz
        do {
            try pdfData.write(to: saveURL)
            convertedFileURL = saveURL
            print("Dosya başarıyla kaydedildi: \(saveURL.path)")
        } catch {
            print("Hata: PDF'ye yazma işlemi sırasında hata oluştu.")
        }
    }
    
    // Office dosyasını PDF'ye dönüştürme işlemi
    func convertOfficeToPDF(officeURL: URL, saveURL: URL) {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = [
            "libreoffice",
            "--headless",
            "--convert-to", "pdf",
            "--outdir", saveURL.deletingLastPathComponent().path,
            officeURL.path
        ]
        
        task.launch()
        task.waitUntilExit()
        
        // Dosyanın başarılı bir şekilde kaydedildiğini kontrol et
        let convertedFilePath = saveURL.path
        if FileManager.default.fileExists(atPath: convertedFilePath) {
            convertedFileURL = URL(fileURLWithPath: convertedFilePath)
            print("Dosya başarıyla kaydedildi: \(convertedFileURL!.path)")
        } else {
            print("Hata: Office dosyasını dönüştürürken bir sorun oluştu.")
        }
    }
    
    // Özel karakterleri temizleyen fonksiyon
    func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let sanitizedFileName = fileName.components(separatedBy: invalidCharacters)
            .joined()
        return sanitizedFileName
    }
}

struct ConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
