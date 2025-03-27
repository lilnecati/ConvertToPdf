import SwiftUI
import PDFKit
import Cocoa
import AppKit
import Foundation
import QuickLookThumbnailing
import Quartz

// Dosya ve format dönüştürme fonksiyonları
class FileConverter {
    
    // Dönüşüm tipleri
    enum ConversionType {
        case PDFToJPEG
        case PDFToJPG
        case PDFToPNG
        case PDFToPDF
        case ImageToPDF
        case OfficeToPDF
        case Unknown
    }
    
    // Dönüşüm tipini belirle
    static func determineConversionType(inputFormat: String, outputFormat: String) -> ConversionType {
        switch (inputFormat, outputFormat) {
        case ("pdf", "jpg"), ("pdf", "jpeg"):
            return .PDFToJPEG
        case ("pdf", "png"):
            return .PDFToPNG
        case ("pdf", "pdf"):
            return .PDFToPDF
        case ("jpg", "pdf"), ("jpeg", "pdf"), ("png", "pdf"):
            return .ImageToPDF
        case ("doc", "pdf"), ("docx", "pdf"), ("ppt", "pdf"), ("pptx", "pdf"), ("xls", "pdf"), ("xlsx", "pdf"):
            return .OfficeToPDF
        default:
            return .Unknown
        }
    }
    
    // PDF'yi JPG'ye dönüştürme işlemi
    static func convertPDFToJPEG(pdfURL: URL, saveURL: URL, progressUpdate: @escaping (Double) -> Void, completion: @escaping (Bool, URL?) -> Void) {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            completion(false, nil)
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
        
            // NSImage'yi JPEG'e dönüştürme işlemi
            if let bitmapRep = NSBitmapImageRep(data: image.tiffRepresentation!) {
                guard let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                    continue
                }
                
                // Her sayfa için yeni bir dosya adı oluştur
                let pageFileName = "\(baseName)_sayfa\(pageIndex + 1).jpg"
                let pageURL = saveDirectory.appendingPathComponent(pageFileName)
                
                do {
                    try jpegData.write(to: pageURL)
                    successCount += 1
                    progressUpdate(Double(successCount) / Double(pageCount))
                    print("✅ Sayfa \(pageIndex + 1) kaydedildi")
                } catch {
                    print("⚠️ Sayfa \(pageIndex + 1) kaydedilirken hata")
                }
            }
        }
        
        if successCount > 0 {
            progressUpdate(1.0)
            print("✅ \(successCount) sayfa başarıyla JPEG olarak dönüştürüldü")
            completion(true, saveDirectory)
        } else {
            completion(false, nil)
        }
    }
    
    // PDF'yi PNG'ye dönüştürme işlemi
    static func convertPDFToPNG(pdfURL: URL, saveURL: URL, progressUpdate: @escaping (Double) -> Void, completion: @escaping (Bool, URL?) -> Void) {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            completion(false, nil)
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
                    progressUpdate(Double(successCount) / Double(pageCount))
                    print("✅ Sayfa \(pageIndex + 1) kaydedildi")
                } catch {
                    print("⚠️ Sayfa \(pageIndex + 1) kaydedilirken hata")
                }
            }
        }
        
        if successCount > 0 {
            progressUpdate(1.0)
            print("✅ \(successCount) sayfa başarıyla PNG olarak dönüştürüldü")
            completion(true, saveDirectory)
        } else {
            completion(false, nil)
        }
    }
    
    // PDF'yi PDF'ye dönüştürme işlemi (kopyalama işlemi)
    static func convertPDFToPDF(pdfURL: URL, saveURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            completion(false, nil)
            return
        }
        
        // PDF'i yeni konuma kaydet
        if pdfDocument.write(to: saveURL) {
            print("✅ PDF dosyası başarıyla kaydedildi")
            completion(true, saveURL)
        } else {
            completion(false, nil)
        }
    }
    
    // JPG veya PNG'yi PDF'ye dönüştürme işlemi
    static func convertImageToPDF(imageURL: URL, saveURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        guard let image = NSImage(contentsOf: imageURL) else {
            completion(false, nil)
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
                print("✅ Görsel PDF'ye başarıyla dönüştürüldü")
                completion(true, saveURL)
            } else {
                completion(false, nil)
            }
        } else {
            completion(false, nil)
        }
    }
    
    // LibreOffice ile dosyayı dönüştür
    static func convertWithLibreOffice(fileURL: URL, saveURL: URL, completion: @escaping (Bool, URL?) -> Void) {
        let fileExtension = fileURL.pathExtension.lowercased()
        
        // Uygun dosya uzantılarını kontrol et
        let officeExtensions = ["doc", "docx", "xls", "xlsx", "ppt", "pptx"]
        guard officeExtensions.contains(fileExtension) else {
            completion(false, nil)
            return
        }
        
        print("🔄 Dönüştürme işlemi başladı")
        print("📄 Kaynak: \(fileURL.lastPathComponent)")
        print("📥 Hedef: \(saveURL.lastPathComponent)")
        
        // Doğrudan kullanıcının seçtiği konuma dönüştür
        convertWithClassicLibreOffice(fileURL: fileURL, saveURL: saveURL) { success, resultURL in
            if success, let resultURL = resultURL {
                // Başarılı, PDF dosyasını kontrol et
                if let pdfDocument = PDFDocument(url: resultURL) {
                    let pageCount = pdfDocument.pageCount
                    print("✅ \(fileExtension.uppercased()) dosyası başarıyla dönüştürüldü (Sayfa sayısı: \(pageCount))")
                    completion(true, resultURL)
                } else {
                    print("⚠️ PDF dosyası oluşturuldu ancak açılamadı")
                    completion(true, resultURL)
                }
            } else {
                print("❌ LibreOffice dönüştürme başarısız oldu")
                completion(false, nil)
            }
        }
    }
    
    // Alternatif LibreOffice çağırma metodu
    private static func convertWithClassicLibreOffice(fileURL: URL, saveURL: URL, onComplete: @escaping (Bool, URL?) -> Void) {
        let officePath = "/Applications/LibreOffice.app/Contents/MacOS/soffice"
        let saveDirectory = saveURL.deletingLastPathComponent().path
        
        print("🔄 Dönüştürme işlemi başladı")
        print("📄 Kaynak: \(fileURL.lastPathComponent)")
        print("📥 Hedef: \(saveURL.lastPathComponent)")
        
        // LibreOffice script içeriği
        let scriptContent = """
        #!/bin/bash
        
        # Hata mesajlarını ve çıktıyı gösterme
        exec 2>/dev/null
        
        # Önceki bir dosya varsa sil
        if [ -f "\(saveURL.path)" ]; then
            rm "\(saveURL.path)"
        fi
        
        # Dizin yoksa oluştur
        mkdir -p "\(saveDirectory)"
        
        # LibreOffice'i doğrudan hedef dosyaya dönüştür
        "\(officePath)" --headless --nologo --nofirststartwizard --norestore --convert-to pdf --outdir "\(saveDirectory)" "\(fileURL.path)"
        
        # Çıkış kodu
        EXIT_CODE=$?
        
        # Oluşturulan dosyayı kontrol et
        if [ -f "\(saveURL.path)" ]; then
            # Dosya zaten istenen konumda oluşturuldu
            exit 0
        else
            # Dosya farklı bir isimle oluşturulmuş olabilir, taşı
            BASENAME=$(basename "\(fileURL.path)" | sed 's/\\.[^.]*$//')
            GENERATED_PDF="\(saveDirectory)/${BASENAME}.pdf"
            
            if [ -f "$GENERATED_PDF" ]; then
                mv "$GENERATED_PDF" "\(saveURL.path)"
                exit 0
            else
                # Hiçbir PDF oluşturulmadı
                exit $EXIT_CODE
            fi
        fi
        """
        
        // Geçici script dosyasını oluştur
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("libreoffice_convert.sh")
        
        do {
            try scriptContent.write(to: scriptURL, atomically: true, encoding: String.Encoding.utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            // Script'i yürüt
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = [scriptURL.path]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            try task.run()
            task.waitUntilExit()
            
            // Çıktıyı oku ama gösterme
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            _ = String(data: outputData, encoding: .utf8)
            
            // Script çalıştırma başarılı mı?
            if task.terminationStatus == 0 {
                // Dosya hedef konumda var mı?
                if FileManager.default.fileExists(atPath: saveURL.path) {
                    print("✅ Dönüştürme tamamlandı")
                    onComplete(true, saveURL)
                } else {
                    print("⚠️ Hedef bulunamadı, diğer PDF dosyaları kontrol ediliyor...")
                    // Dizindeki PDF dosyalarını kontrol et
                    if let filesInDir = try? FileManager.default.contentsOfDirectory(atPath: saveDirectory) {
                        let pdfFiles = filesInDir.filter { $0.hasSuffix(".pdf") }
                        if let firstPDF = pdfFiles.first {
                            let foundPDF = URL(fileURLWithPath: saveDirectory).appendingPathComponent(firstPDF)
                            do {
                                try FileManager.default.moveItem(at: foundPDF, to: saveURL)
                                print("✅ PDF bulundu ve taşındı")
                                onComplete(true, saveURL)
                            } catch {
                                print("⚠️ Dosya taşıma hatası")
                                onComplete(true, foundPDF)
                            }
                            return
                        }
                    }
                    print("❌ PDF dosyası bulunamadı")
                    onComplete(false, nil)
                }
            } else {
                print("❌ LibreOffice dönüştürme başarısız oldu")
                onComplete(false, nil)
            }
            
            // Geçici script dosyasını temizle
            try? FileManager.default.removeItem(at: scriptURL)
            
        } catch {
            print("❌ Script oluşturulamadı: \(error)")
            onComplete(false, nil)
        }
    }
}
