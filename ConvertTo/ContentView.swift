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
    @State private var showConversionSuccess = false
    
    // Dönüştürme seçenekleri için yeni state değişkenleri
    @State private var showConversionOptions = false
    @State private var availableConversionTypes: [String] = []
    @State private var selectedConversionType: String = "PDF"
    
    // Kurulu bileşenler için state değişkenleri
    @State private var hasImageMagick = false
    @State private var hasTesseract = false
    @State private var hasLibreOffice = false
    @State private var showSettings = false
    
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
    
    // Desteklenen formatlar
    let supportedFormats: [String: [String]] = [
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
    let supportedExtensions = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "jpg", "jpeg", "png"]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Dönüştürülecek Dosya")) {
                    HStack {
                        Text(selectedFileURL?.lastPathComponent ?? "Dosya seçilmedi")
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button("Dosya Seç") {
                            self.selectFile()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 5)
                    
                    if let filePreview = generatePreviewImage(for: selectedFileURL) {
                        Image(nsImage: filePreview)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                    }
                }
                
                if selectedFileURL != nil {
                    Section(header: Text("Çıktı Formatı")) {
                        Picker("Format", selection: $selectedConversionType) {
                            if let inputExt = selectedFileURL?.pathExtension.uppercased(),
                               let supportedOutputs = supportedFormats[inputExt] {
                                ForEach(supportedOutputs, id: \.self) { format in
                                    Text(format).tag(format)
                                }
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    Section {
                        Button(action: {
                            if let selectedFile = selectedFileURL,
                               !selectedConversionType.isEmpty {
                                convertFile(inputURL: selectedFile, outputFormat: selectedConversionType.lowercased())
                            }
                        }) {
                            if isConverting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 5)
                                Text("Dönüştürülüyor...")
                            } else {
                                Text("Dönüştür")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(isConverting || selectedFileURL == nil || selectedConversionType.isEmpty)
                        .buttonStyle(.borderedProminent)
                        
                        if isConverting {
                            ProgressView(value: conversionProgress)
                        }
                    }
                }
            }
            .padding()
            .frame(minWidth: 400, maxWidth: 600)
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Hata"),
                    message: Text(errorMessage ?? "Bilinmeyen bir hata oluştu"),
                    dismissButton: .default(Text("Tamam"))
                )
            }
            .sheet(isPresented: $showConversionSuccess) {
                ConversionSuccessView(fileURL: convertedFileURL)
            }
            .navigationTitle("ConvertTo - Dosya Dönüştürücü")
        }
    }
    
    // Mevcut kurulu bileşenleri kontrol et
    func checkOptimalSettings() {
        // Tesseract OCR kontrolü
        let tesseractPaths = [
            "/opt/homebrew/bin/tesseract",
            "/usr/local/bin/tesseract",
            "/usr/bin/tesseract"
        ]
        
        hasTesseract = false
        for path in tesseractPaths {
            if FileManager.default.fileExists(atPath: path) {
                hasTesseract = true
                break
            }
        }
        
        // ImageMagick kontrolü
        let convertPaths = [
            "/opt/homebrew/bin/convert",
            "/usr/local/bin/convert",
            "/usr/bin/convert"
        ]
        
        hasImageMagick = false
        for path in convertPaths {
            if FileManager.default.fileExists(atPath: path) {
                hasImageMagick = true
                break
            }
        }
        
        // LibreOffice kontrolü
        let libreOfficePaths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/usr/local/bin/soffice",
            "/opt/homebrew/bin/soffice"
        ]
        
        hasLibreOffice = false
        for path in libreOfficePaths {
            if FileManager.default.fileExists(atPath: path) {
                hasLibreOffice = true
                break
            }
        }
    }
    
    // LibreOffice kurulumu için yardımcı fonksiyon
    func offerLibreOfficeInstallation() {
        let alert = NSAlert()
        alert.messageText = "LibreOffice Eksik"
        alert.informativeText = """
        Office dosyalarını dönüştürmek için LibreOffice gereklidir.
        
        LibreOffice'i yüklemek için Terminal'de şu komutu çalıştırın:
        
        brew install --cask libreoffice
        
        Homebrew yüklü değilse, önce şu komutu çalıştırmalısınız:
        
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        Alternatif olarak, LibreOffice web sitesinden de indirebilirsiniz.
        """
        alert.addButton(withTitle: "Tamam")
        alert.addButton(withTitle: "LibreOffice Web Sitesi")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            // LibreOffice web sitesini aç
            if let url = URL(string: "https://www.libreoffice.org/download/download/") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // Tesseract OCR kurulumu için yardımcı fonksiyon
    func offerTesseractInstallation() {
        let alert = NSAlert()
        alert.messageText = "Tesseract OCR Eksik"
        alert.informativeText = """
        PDF'den Office formatlarına dönüştürme için Tesseract OCR gereklidir.
        
        Tesseract OCR'ı yüklemek için Terminal'de şu komutu çalıştırın:
        
        brew install tesseract
        
        Türkçe dil desteği için:
        
        brew install tesseract-lang
        
        Homebrew yüklü değilse, önce şu komutu çalıştırmalısınız:
        
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        """
        alert.addButton(withTitle: "Tamam")
        alert.addButton(withTitle: "Tesseract Web Sitesi")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            // Tesseract web sitesini aç
            if let url = URL(string: "https://github.com/tesseract-ocr/tesseract") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    // ImageMagick kurulumu için yardımcı fonksiyon
    func offerImageMagickInstallation() {
        let alert = NSAlert()
        alert.messageText = "ImageMagick Eksik"
        alert.informativeText = """
        Gelişmiş görüntü işleme ve OCR optimizasyonu için ImageMagick gereklidir.
        
        ImageMagick'i yüklemek için Terminal'de şu komutu çalıştırın:
        
        brew install imagemagick
        
        Homebrew yüklü değilse, önce şu komutu çalıştırmalısınız:
        
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        """
        alert.addButton(withTitle: "Tamam")
        alert.addButton(withTitle: "ImageMagick Web Sitesi")
        
        let response = alert.runModal()
        
        if response == .alertSecondButtonReturn {
            // ImageMagick web sitesini aç
            if let url = URL(string: "https://imagemagick.org/script/download.php") {
                NSWorkspace.shared.open(url)
            }
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
            // Dosya türüne göre olası dönüştürme seçeneklerini belirle
            if let fileURL = panel.url {
                setConversionOptions(for: fileURL)
            }
        }
    }
    
    // Dosya türüne göre dönüştürme seçeneklerini belirle
    func setConversionOptions(for fileURL: URL) {
        let fileExtension = fileURL.pathExtension.lowercased()
        
        switch fileExtension {
        case "docx", "doc", "rtf", "txt", "odt":
            availableConversionTypes = ["PDF", "Metin", "HTML", "DOCX"]
        case "ppt", "pptx":
            availableConversionTypes = ["PDF", "PNG Slaytlar", "HTML"]
        case "xlsx", "xls", "csv", "ods":
            availableConversionTypes = ["PDF", "CSV", "HTML"]
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "webp", "heic":
            availableConversionTypes = ["PDF", "JPEG", "PNG", "TIFF"]
        case "pdf":
            // PDF'den Office formatlarına dönüştürme seçeneklerini ekledik
            availableConversionTypes = ["PNG", "JPEG", "Metin", "DOCX", "PPT", "XLS"]
        default:
            availableConversionTypes = ["PDF"]
        }
        
        // Dönüştürme seçenekleri penceresini otomatik göster
        showConversionOptions = true
    }
    
    // Dönüşüm tipini belirle
    func determineConversionType(inputFormat: String, outputFormat: String) -> ConversionType {
        switch (inputFormat.lowercased(), outputFormat.lowercased()) {
        case ("pdf", "jpg"), ("pdf", "jpeg"):
            return .PDFToJPG
        case ("pdf", "png"):
            return .PDFToPNG
        case ("pdf", "pdf"):
            return .PDFToPDF
        case ("jpg", "pdf"), ("jpeg", "pdf"), ("png", "pdf"):
            return .ImageToPDF
        case ("docx", "pdf"), ("doc", "pdf"), ("pptx", "pdf"), ("ppt", "pdf"), ("xlsx", "pdf"), ("xls", "pdf"):
            return .OfficeToPDF
        default:
            return .Unknown
        }
    }
    
    // Dosyayı dönüştürme işlemi
    func convertFile(inputURL: URL, outputFormat: String) {
        guard !isConverting else { return }
        
        let inputFormat = inputURL.pathExtension.lowercased()
        let conversionType = determineConversionType(inputFormat: inputFormat, outputFormat: outputFormat)
        
        if conversionType == .Unknown {
            print("Desteklenmeyen dönüşüm: \(inputFormat) -> \(outputFormat)")
            self.showError("Bu dönüşüm tipi desteklenmiyor: \(inputFormat) -> \(outputFormat)")
            return
        }
        
        // Kaydedilecek dosya yolunu belirle
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [UTType(filenameExtension: outputFormat) ?? .plainText]
        // Dosya adını orijinal isim olarak ayarla, uzantısını değiştir
        savePanel.nameFieldStringValue = inputURL.deletingPathExtension().lastPathComponent + "." + outputFormat
        
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else {
            return
        }
        
        isConverting = true
        conversionProgress = 0.0
        
        // Doğru dönüşüm fonksiyonunu çağır
        switch conversionType {
        case .PDFToJPEG, .PDFToJPG:
            convertPDFToJPEG(pdfURL: inputURL, saveURL: saveURL)
        case .PDFToPNG:
            convertPDFToPNG(pdfURL: inputURL, saveURL: saveURL)
        case .PDFToPDF:
            convertPDFToPDF(pdfURL: inputURL, saveURL: saveURL)
        case .ImageToPDF:
            convertImageToPDF(imageURL: inputURL, saveURL: saveURL)
        case .OfficeToPDF:
            convertOfficeToPDF(officeURL: inputURL, saveURL: saveURL)
        default:
            isConverting = false
            self.showError("Bu dönüşüm şu anda desteklenmiyor")
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
    func generatePreviewImage(for fileURL: URL?) -> NSImage? {
        guard let fileURL = fileURL else { return nil }
        
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
    
    // LibreOffice ile dosyayı dönüştür
    func convertWithLibreOffice(fileURL: URL, saveURL: URL) {
        let fileExtension = fileURL.pathExtension.lowercased()
        
        // Uygun dosya uzantılarını kontrol et
        let officeExtensions = ["doc", "docx", "xls", "xlsx", "ppt", "pptx"]
        guard officeExtensions.contains(fileExtension) else {
            showError("Bu dosya tipi Office dönüşümü için desteklenmiyor: \(fileExtension)")
            return
        }
        
        print("🔄 Dönüştürme işlemi başladı")
        print("📄 Kaynak: \(fileURL.lastPathComponent)")
        print("📥 Hedef: \(saveURL.lastPathComponent)")
        
        // Doğrudan kullanıcının seçtiği konuma dönüştür
        self.convertWithClassicLibreOffice(fileURL: fileURL, saveURL: saveURL, onComplete: { success, resultURL in
            DispatchQueue.main.async {
                if success, let resultURL = resultURL {
                    // Başarılı, PDF dosyasını kontrol et
                    if let pdfDocument = PDFDocument(url: resultURL) {
                        let pageCount = pdfDocument.pageCount
                        self.convertedFileURL = resultURL
                        self.isConverting = false
                        self.conversionProgress = 1.0
                        self.showConversionSuccess = true
                        
                        print("✅ \(fileExtension.uppercased()) dosyası başarıyla dönüştürüldü (Sayfa sayısı: \(pageCount))")
                    } else {
                        self.showError("PDF dosyası oluşturuldu ancak açılamadı.")
                    }
                } else {
                    self.showError("LibreOffice dönüştürme başarısız oldu.")
                }
            }
        })
    }
    
    // Alternatif LibreOffice çağırma metodu
    func convertWithClassicLibreOffice(fileURL: URL, saveURL: URL, onComplete: @escaping (Bool, URL?) -> Void) {
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
    
    // PDF'den JPEG'e dönüştürme işlemi
    func convertPDFToJPEG(pdfURL: URL, saveURL: URL) {
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
            print("\(successCount) sayfa başarıyla JPEG olarak dönüştürüldü")
        } else {
            showError("Hiçbir sayfa dönüştürülemedi")
        }
    }
}

struct ConversionSuccessView: View {
    var fileURL: URL?
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 60, height: 60)
                .foregroundColor(.green)
            
            Text("Dönüştürme Başarılı")
                .font(.title)
                .fontWeight(.bold)
            
            if let fileURL = fileURL {
                Text("Dosya konumu:")
                    .font(.headline)
                
                Text(fileURL.path)
                    .font(.body)
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Button("Dosyayı Klasörde Göster") {
                    NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: fileURL.deletingLastPathComponent().path)
                }
                .padding()
                .buttonStyle(.borderedProminent)
            }
            
            Button("Tamam") {
                presentationMode.wrappedValue.dismiss()
            }
            .padding(.top)
        }
        .padding(30)
        .frame(width: 500)
    }
}

struct ConverterApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
