import SwiftUI
import PDFKit
import Cocoa
import AppKit
import Foundation
import QuickLookThumbnailing
import Quartz

// Yardımcı fonksiyonlar ve ek yapılar
class Utilities {
    
    // Desteklenen dosya uzantıları ve çevrimler
    static let supportedFormats: [String: [String]] = [
        "PDF": ["DOCX", "PPT", "JPG", "PNG", "PDF"],  // PDF'ten Office dönüşümleri kaldırıldı
        "PPTX": ["PDF"],
        "PPT": ["PDF"],
        "DOCX": ["PDF"],
        "DOC": ["PDF"],
        "XLSX": ["PDF"],
        "XLS": ["PDF"],
        "JPG": ["PDF"],
        "JPEG": ["PDF"],
        "PNG": ["PDF"]
    ]
    
    // Desteklenen uzantılar
    static let supportedExtensions = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "jpg", "jpeg", "png"]
    
    // Önizleme görüntüsünü oluştur
    static func generatePreviewImage(for fileURL: URL?) -> NSImage? {
        guard let fileURL = fileURL else { return nil }
        
        // PDF dosyaları için
        if fileURL.pathExtension.lowercased() == "pdf" {
            if let pdfDocument = PDFDocument(url: fileURL), let pdfPage = pdfDocument.page(at: 0) {
                return pdfPage.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
            }
            return nil
        }
        
        // Resim dosyaları için
        let imageExtensions = ["jpg", "jpeg", "png"]
        if imageExtensions.contains(fileURL.pathExtension.lowercased()) {
            return NSImage(contentsOf: fileURL)
        }
        
        // Diğer dosya türleri için QuickLook önizlemesi - asenkron çalıştırmak daha güvenli
        return generateQuickLookPreview(for: fileURL)
    }
    
    // QuickLook önizleme oluşturmak için ayrı bir metod
    private static func generateQuickLookPreview(for fileURL: URL) -> NSImage? {
        // Varsayılan bir önizleme göster (dosya simgesi)
        let fileIcon = NSWorkspace.shared.icon(forFile: fileURL.path)
        // Dosya simgesini biraz büyüt
        let iconImage = NSImage(size: NSSize(width: 128, height: 128))
        iconImage.lockFocus()
        fileIcon.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128))
        iconImage.unlockFocus()
        return iconImage
    }
    
    // Asenkron önizleme oluşturma (SwiftUI'da kullanılabilir)
    static func generatePreviewImageAsync(for fileURL: URL?, completion: @escaping (NSImage?) -> Void) {
        guard let fileURL = fileURL else {
            completion(nil)
            return
        }
        
        // Ana thread'de çağrılıyorsa, arka plana geç
        DispatchQueue.global(qos: .userInitiated).async {
            var previewImage: NSImage? = nil
            
            // PDF dosyaları için
            if fileURL.pathExtension.lowercased() == "pdf" {
                if let pdfDocument = PDFDocument(url: fileURL), let pdfPage = pdfDocument.page(at: 0) {
                    previewImage = pdfPage.thumbnail(of: CGSize(width: 240, height: 320), for: .cropBox)
                }
            }
            // Resim dosyaları için
            else if ["jpg", "jpeg", "png"].contains(fileURL.pathExtension.lowercased()) {
                previewImage = NSImage(contentsOf: fileURL)
            }
            // Diğer dosya türleri için QuickLook önizlemesi
            else {
                let request = QLThumbnailGenerator.Request(
                    fileAt: fileURL,
                    size: CGSize(width: 240, height: 320),
                    scale: NSScreen.main?.backingScaleFactor ?? 1.0,
                    representationTypes: .thumbnail
                )
                
                let generator = QLThumbnailGenerator.shared
                generator.generateBestRepresentation(for: request) { (thumbnail, error) in
                    if let thumbnail = thumbnail {
                        // Ana thread'e geç ve önizlemeyi güncelle
                        DispatchQueue.main.async {
                            completion(thumbnail.nsImage)
                        }
                    } else {
                        // Hata durumunda dosya simgesini göster
                        DispatchQueue.main.async {
                            let fileIcon = NSWorkspace.shared.icon(forFile: fileURL.path)
                            completion(fileIcon)
                        }
                    }
                }
                // Burada return ederek, generator'ın asenkron işlemini beklemeden döneriz
                return
            }
            
            // PDF veya resim dosyaları için sonucu ana thread'de dön
            DispatchQueue.main.async {
                completion(previewImage)
            }
        }
    }
    
    // Sistem kontrolü ve kurulum durumu tespiti
    static func checkInstalledSoftware() -> (tesseract: Bool, imagemagick: Bool, libreoffice: Bool) {
        let tesseractPath = checkTesseractPath()
        let imagemagickPath = FileManager.default.fileExists(atPath: "/usr/local/bin/convert") || 
                             FileManager.default.fileExists(atPath: "/opt/homebrew/bin/convert")
        let libreofficePath = FileManager.default.fileExists(atPath: "/Applications/LibreOffice.app/Contents/MacOS/soffice")
        
        return (tesseractPath != nil, imagemagickPath, libreofficePath)
    }
    
    // Tesseract OCR'ın yolunu kontrol et
    static func checkTesseractPath() -> String? {
        let potentialPaths = [
            "/usr/local/bin/tesseract",
            "/opt/homebrew/bin/tesseract",
            "/usr/bin/tesseract"
        ]
        
        for path in potentialPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // Tesseract kurulu değil
        return nil
    }
    
    // Hata mesajı göster
    static func showError(_ message: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "Hata"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Tamam")
        return alert
    }
}

// Başarılı dönüştürme ekranı
struct ConversionSuccessView: View {
    var fileURL: URL?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 30) {
            // Başlık ve Icon
            VStack(spacing: 15) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .shadow(color: Color.green.opacity(0.3), radius: 8, x: 0, y: 4)
                
                Text("Dönüştürme Başarılı")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            
            // Dosya Bilgileri
            if let fileURL = fileURL {
                VStack(spacing: 15) {
                    HStack {
                        Text("Dosya:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(fileURL.lastPathComponent)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal)
                    
                    HStack {
                        Text("Konum:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(fileURL.deletingLastPathComponent().path)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal)
                    
                    // Dosya ikonunu ve türünü belirleme
                    let fileExtension = fileURL.pathExtension.uppercased()
                    let (iconName, bgColor) = getFileIconAndColor(fileExtension: fileExtension)
                    
                    // Dosya ikonu ve türü görünümü
                    HStack(spacing: 15) {
                        Image(systemName: iconName)
                            .font(.title)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(bgColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        
                        Text("\(fileExtension) Dosyası")
                            .font(.headline)
                        
                        Spacer()
                    }
                    .padding(.top, 10)
                    .padding(.horizontal)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .background(Color(.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                
                // Butonlar
                HStack(spacing: 15) {
                    Button(action: {
                        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                    }) {
                        HStack {
                            Image(systemName: "folder")
                            Text("Dosyayı Göster")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button(action: {
                        NSWorkspace.shared.open(fileURL)
                    }) {
                        HStack {
                            Image(systemName: "eye")
                            Text("Dosyayı Aç")
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 10)
            }
            
            Spacer()
            
            Button("Tamam") {
                presentationMode.wrappedValue.dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(width: 520, height: 550)
        .background(Color(.windowBackgroundColor), in: Rectangle())
    }
    
    // Dosya türüne göre ikon ve renk belirle
    private func getFileIconAndColor(fileExtension: String) -> (icon: String, color: Color) {
        switch fileExtension {
        case "PDF":
            return ("doc.fill", .red)
        case "DOCX", "DOC", "TXT":
            return ("doc.text.fill", .blue)
        case "JPG", "JPEG", "PNG":
            return ("photo.fill", .purple)
        case "PPT", "PPTX":
            return ("chart.bar.doc.horizontal.fill", .orange)
        case "XLS", "XLSX":
            return ("tablecells.fill", .green)
        default:
            return ("doc.fill", .gray)
        }
    }
}
