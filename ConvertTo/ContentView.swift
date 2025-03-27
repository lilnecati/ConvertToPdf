import SwiftUI
import PDFKit
import Cocoa
import AppKit
import Foundation
import QuickLookThumbnailing
import Quartz

struct ContentView: View {
    @State private var selectedFileURL: URL?
    @State private var convertedFileURL: URL?
    @State private var isConverting = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var conversionProgress: Double = 0
    
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
            
            // İlerleme çubuğu
            if isConverting {
                ProgressView(value: conversionProgress)
                    .padding()
                Text("Dönüştürülüyor... \(Int(conversionProgress * 100))%")
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
        .alert("Hata", isPresented: $showError) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Bilinmeyen bir hata oluştu")
        }
    }
    
    // Dosya seçme işlemi
    func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .pdf,
            .jpeg,
            .png,
            .init(filenameExtension: "doc")!,
            .init(filenameExtension: "docx")!,
            .init(filenameExtension: "xls")!,
            .init(filenameExtension: "xlsx")!,
            .init(filenameExtension: "ppt")!,
            .init(filenameExtension: "pptx")!
        ]
        panel.message = "Lütfen bir dosya seçin"
        if panel.runModal() == .OK {
            selectedFileURL = panel.url
        }
    }
    
    // Seçilen dosyayı dönüştürme işlemi
    func convertFile(_ fileURL: URL) {
        let fileExtension = fileURL.pathExtension.lowercased()
        isConverting = true
        conversionProgress = 0
        
        // Kaydedilecek dosya için konum seç
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        
        switch fileExtension {
            case "docx", "doc", "rtf", "txt", "odt":
                savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent).pdf"
                savePanel.allowedContentTypes = [.pdf]
                savePanel.message = "PDF dosyasını kaydedin"
                savePanel.begin { result in
                    if result == .OK, let saveURL = savePanel.url {
                        // Word dosyaları için de LibreOffice ile dönüştürme işlemi kullanacağız
                        DispatchQueue.global(qos: .userInteractive).async {
                            self.convertWithLibreOffice(fileURL: fileURL, saveURL: saveURL)
                        }
                    } else {
                        isConverting = false
                    }
                }
                
            case "ppt", "pptx":
                // PowerPoint dosyaları için doğrudan LibreOffice dönüştürücü
                savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent).pdf"
                savePanel.allowedContentTypes = [.pdf]
                savePanel.message = "PDF dosyasını kaydedin"
                savePanel.begin { result in
                    if result == .OK, let saveURL = savePanel.url {
                        // Doğrudan LibreOffice ile dönüştürme işlemi
                        DispatchQueue.global(qos: .userInteractive).async {
                            self.convertWithLibreOffice(fileURL: fileURL, saveURL: saveURL)
                        }
                    } else {
                        isConverting = false
                    }
                }
                
            case "xlsx", "xls", "csv", "ods":
                savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent).pdf"
                savePanel.allowedContentTypes = [.pdf]
                savePanel.message = "PDF dosyasını kaydedin"
                savePanel.begin { result in
                    if result == .OK, let saveURL = savePanel.url {
                        self.convertOfficeToPDF(officeURL: fileURL, saveURL: saveURL)
                    } else {
                        isConverting = false
                    }
                }
                
            case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic":
                savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent).pdf"
                savePanel.allowedContentTypes = [.pdf]
                savePanel.message = "PDF dosyasını kaydedin"
                savePanel.begin { result in
                    if result == .OK, let saveURL = savePanel.url {
                        self.convertImageToPDF(imageURL: fileURL, saveURL: saveURL)
                    } else {
                        isConverting = false
                    }
                }
                
            case "pdf":
                savePanel.nameFieldStringValue = "\(fileURL.deletingPathExtension().lastPathComponent)_convert.pdf"
                savePanel.allowedContentTypes = [.pdf]
                savePanel.message = "PDF dosyasını kaydedin"
                savePanel.begin { result in
                    if result == .OK, let saveURL = savePanel.url {
                        self.convertPDFToPDF(pdfURL: fileURL, saveURL: saveURL)
                    } else {
                        isConverting = false
                    }
                }
                
            default:
                DispatchQueue.main.async {
                    self.showError("Bu dosya türü desteklenmiyor")
                }
                isConverting = false
        }
    }
    
    // PDF'yi PNG'ye dönüştürme işlemi
    func convertPDFToPNG(pdfURL: URL, saveURL: URL) {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            showError("PDF dosyası açılamadı")
            return
        }
        
        let pageCount = pdfDocument.pageCount
        var successCount = 0
        
        // Kayıt dizinini al
        let saveDirectory = saveURL.deletingLastPathComponent()
        let baseName = saveURL.deletingPathExtension().lastPathComponent
        
        for pageIndex in 0..<pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else {
                continue
            }
            
            // Sayfanın boyutlarını al
            let pageRect = page.bounds(for: .mediaBox)
            let scale: CGFloat = 2.0 // Çözünürlük çarpanı
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            // Sayfayı thumbnail olarak al
            let image = page.thumbnail(of: size, for: .mediaBox)
        
        // NSImage'yi PNG'ye dönüştürme işlemi
        if let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!) {
            guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                    continue
                }
                
                // Her sayfa için yeni bir dosya adı oluştur
                let pageFileName = "\(baseName)_sayfa\(pageIndex + 1).png"
                let pageURL = saveDirectory.appendingPathComponent(pageFileName)
                
                do {
                    try pngData.write(to: pageURL)
                    successCount += 1
                    conversionProgress = Double(successCount) / Double(pageCount)
                    print("Sayfa \(pageIndex + 1) kaydedildi: \(pageURL.path)")
            } catch {
                    print("Sayfa \(pageIndex + 1) kaydedilirken hata: \(error.localizedDescription)")
                }
            }
        }
        
        if successCount > 0 {
            convertedFileURL = saveDirectory
            isConverting = false
            conversionProgress = 1.0
            print("\(successCount) sayfa başarıyla dönüştürüldü")
        } else {
            showError("Hiçbir sayfa dönüştürülemedi")
        }
    }
    
    // JPG veya PNG'yi PDF'ye dönüştürme işlemi
    func convertImageToPDF(imageURL: URL, saveURL: URL) {
        guard let image = NSImage(contentsOf: imageURL) else {
            showError("Görsel açılamadı")
            return
        }
        
        // PDF belgesi oluştur
        let pdfDocument = PDFDocument()
        
        // Görüntüyü PDF sayfasına dönüştür
        if let page = PDFPage(image: image) {
            // Sayfayı PDF'e ekle
            pdfDocument.insert(page, at: 0)
            
            // PDF'i kaydet
            if pdfDocument.write(to: saveURL) {
            convertedFileURL = saveURL
                isConverting = false
                conversionProgress = 1.0
            print("Dosya başarıyla kaydedildi: \(saveURL.path)")
            } else {
                showError("PDF dosyası kaydedilemedi")
            }
        } else {
            showError("Görsel PDF'ye dönüştürülemedi")
        }
    }
    
    // Office dosyasını PDF'ye dönüştürme işlemi
    func convertOfficeToPDF(officeURL: URL, saveURL: URL) {
        // Doğrudan LibreOffice metoduna yönlendir
        convertWithLibreOffice(fileURL: officeURL, saveURL: saveURL)
    }
    
    // Dosyanın önizleme görüntüsünü oluştur
    func generatePreviewImage(for fileURL: URL) -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: 1920, height: 1080),
            scale: 2.0,
            representationTypes: .all
        )
        
        var thumbnail: NSImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        // QoS değerini tutarlı tutalım
        let qosClass = DispatchQoS.QoSClass.userInitiated
        let generator = QLThumbnailGenerator.shared
        
        generator.generateBestRepresentation(for: request) { (representation, error) in
            DispatchQueue.global(qos: qosClass).async {
                if let representation = representation {
                    let cgImage = representation.cgImage
                    thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                }
                semaphore.signal()
            }
        }
        
        // Kısa bir süre bekle
        _ = semaphore.wait(timeout: .now() + 3.0)
        
        return thumbnail
    }
    
    // İki görüntünün benzer olup olmadığını kontrol et
    func imagesAreSimilar(_ image1: NSImage?, _ image2: NSImage?, threshold: Double = 0.45) -> Bool {
        return false // Bu fonksiyon artık kullanılmadığı için her zaman false döndürüyoruz
    }
    
    // İki rengin benzer olup olmadığını kontrol et
    func colorsAreSimilar(_ color1: NSColor?, _ color2: NSColor?, threshold: Double = 0.1) -> Bool {
        return false // Bu fonksiyon artık kullanılmadığı için her zaman false döndürüyoruz
    }
    
    // Özel karakterleri temizleyen fonksiyon
    func sanitizeFileName(_ fileName: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let sanitizedFileName = fileName.components(separatedBy: invalidCharacters)
            .joined()
        return sanitizedFileName
    }
    
    // Hata gösterme fonksiyonu
    private func showError(_ message: String) {
        errorMessage = message
        showError = true
        isConverting = false
        conversionProgress = 0
    }
    
    // LibreOffice ile doğrudan Office dönüştürme işlemi (Python olmadan)
    func convertWithLibreOffice(fileURL: URL, saveURL: URL) {
        let fileExtension = fileURL.pathExtension.lowercased()
        
        print("LibreOffice ile \(fileExtension.uppercased()) dönüştürme başladı")
        DispatchQueue.main.async {
            self.conversionProgress = 0.1
        }
        
        // LibreOffice yollarını kontrol et
        let libreOfficePaths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/usr/local/bin/soffice",
            "/opt/homebrew/bin/soffice"
        ]
        
        var officePathExists = false
        var officePath = ""
        
        for path in libreOfficePaths {
            if FileManager.default.fileExists(atPath: path) {
                officePathExists = true
                officePath = path
                break
            }
        }
        
        if !officePathExists {
            DispatchQueue.main.async {
                self.showError("LibreOffice bulunamadı. Lütfen LibreOffice'i yükleyin: brew install --cask libreoffice")
            }
            return
        }
        
        // PDF'in kaydedileceği klasörü al
        let saveDirectory = saveURL.deletingLastPathComponent().path
        
        // LibreOffice komutunu çalıştır
        let task = Process()
        task.executableURL = URL(fileURLWithPath: officePath)
        task.arguments = [
            "--headless",
            "--convert-to", "pdf",
            "--outdir", saveDirectory,
            fileURL.path
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        DispatchQueue.main.async {
            self.conversionProgress = 0.3
        }
        
        do {
            try task.run()
            
            // Çıktıyı takip et
            let outputHandle = pipe.fileHandleForReading
            var outputData = Data()
            
            outputHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.count > 0 {
                    outputData.append(data)
                    if let output = String(data: data, encoding: .utf8) {
                        print("LibreOffice çıktısı: \(output)")
                    }
                }
            }
            
            task.waitUntilExit()
            
            // Çıktıyı temizle
            outputHandle.readabilityHandler = nil
            
            DispatchQueue.main.async {
                self.conversionProgress = 0.7
            }
            
            // İşlem başarılı mı kontrol et
            if task.terminationStatus == 0 {
                // LibreOffice çıktı dosyasının adını belirle
                let baseName = fileURL.deletingPathExtension().lastPathComponent
                let libreOfficeOutput = URL(fileURLWithPath: saveDirectory).appendingPathComponent("\(baseName).pdf")
                
                // Çıktı oluşturuldu mu kontrol et
                if FileManager.default.fileExists(atPath: libreOfficeOutput.path) {
                    // Eğer çıktı istenen konumdan farklıysa taşı
                    if libreOfficeOutput.path != saveURL.path {
                        do {
                            if FileManager.default.fileExists(atPath: saveURL.path) {
                                try FileManager.default.removeItem(at: saveURL)
                            }
                            try FileManager.default.moveItem(at: libreOfficeOutput, to: saveURL)
                        } catch {
                            print("Dosya taşıma hatası: \(error)")
                            DispatchQueue.main.async {
                                self.showError("Dönüştürme tamamlandı ancak dosya kaydedilemedi: \(error.localizedDescription)")
                            }
                            return
                        }
                    }
                    
                    // PDF belgesini açıp sayfa sayısını kontrol et
                    if let pdfDocument = PDFDocument(url: saveURL) {
                        let pageCount = pdfDocument.pageCount
                        
                        DispatchQueue.main.async {
                            self.convertedFileURL = saveURL
                            self.isConverting = false
                            self.conversionProgress = 1.0
                        }
                        
                        print("\(fileExtension.uppercased()) dosyası LibreOffice ile başarıyla dönüştürüldü: \(saveURL.path) (Sayfa sayısı: \(pageCount))")
                    } else {
                        DispatchQueue.main.async {
                            self.showError("PDF dosyası oluşturuldu ancak açılamadı.")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.showError("LibreOffice PDF çıktısı oluşturulamadı")
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.showError("LibreOffice dönüştürme hatası")
                }
            }
        } catch {
            print("LibreOffice işlemi başlatılamadı: \(error)")
            DispatchQueue.main.async {
                self.showError("LibreOffice işlemi başlatılamadı: \(error.localizedDescription)")
            }
        }
    }
    
    // PDF'yi PDF'ye dönüştürme işlemi
    func convertPDFToPDF(pdfURL: URL, saveURL: URL) {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            showError("PDF dosyası açılamadı")
            return
        }
        
        // PDF'i yeni konuma kaydet
        if pdfDocument.write(to: saveURL) {
            convertedFileURL = saveURL
            isConverting = false
            conversionProgress = 1.0
            print("PDF dosyası başarıyla kaydedildi: \(saveURL.path)")
        } else {
            showError("PDF dosyası kaydedilemedi")
        }
    }
}

struct ConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
