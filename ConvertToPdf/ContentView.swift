import SwiftUI
import PDFKit
import Cocoa
import AppKit
import Foundation
import QuickLookThumbnailing
import Quartz

// Son dönüşümleri tutmak için model
struct ConversionRecord: Identifiable, Equatable, Codable {
    var id: UUID
    let fileName: String
    let fileURL: URL
    let date: Date
    let fileType: String
    let fileSize: Int64
    
    init(fileName: String, fileURL: URL, date: Date, fileType: String, fileSize: Int64) {
        self.id = UUID()
        self.fileName = fileName
        self.fileURL = fileURL
        self.date = date
        self.fileType = fileType
        self.fileSize = fileSize
    }
}

class RecentConversionsManager: ObservableObject {
    @Published var recentConversions: [ConversionRecord] = []
    private let maxRecords = 10
    private let defaults = UserDefaults.standard
    private let storageKey = "recentConversions"
    
    init() {
        loadSavedConversions()
    }
    
    private func loadSavedConversions() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ConversionRecord].self, from: data) {
            recentConversions = decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
        }
    }
    
    private func saveConversions() {
        if let encoded = try? JSONEncoder().encode(recentConversions) {
            defaults.set(encoded, forKey: storageKey)
        }
    }
    
    func addConversion(fileName: String, fileURL: URL) {
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        let fileType = fileURL.pathExtension.uppercased()
        
        let newRecord = ConversionRecord(
            fileName: fileName,
            fileURL: fileURL,
            date: Date(),
            fileType: fileType,
            fileSize: fileSize
        )
        
        recentConversions.insert(newRecord, at: 0)
        if recentConversions.count > maxRecords {
            recentConversions.removeLast()
        }
        
        saveConversions()
    }
    
    func openPDF(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
    
    func removeConversion(_ record: ConversionRecord) {
        recentConversions.removeAll { $0.id == record.id }
        saveConversions()
    }
}

struct ContentView: View {
    @ObservedObject private var conversionVM = ConversionViewModel()
    @ObservedObject private var fileSelectionVM = FileSelectionViewModel()
    @ObservedObject private var recentConversionsManager = RecentConversionsManager()
    @State private var selectedConversionType: String = "PDF"
    @State private var showSettings = false
    @State private var previewImage: NSImage? = nil
    
    // Kurulu bileşenler için state değişkenleri
    @State private var hasImageMagick = false
    @State private var hasTesseract = false
    @State private var hasLibreOffice = false
    
    // Özel renkler
    private let accentColor = Color.blue
    private let backgroundColor = Color(.windowBackgroundColor)
    private let cardBackground = Color(.controlBackgroundColor)
    
    var body: some View {
        NavigationView {
            // Sol taraf - Ana içerik
            ZStack {
                backgroundColor.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 24) {
                    // Header
                    Text("ConvertToPdf")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .padding(.top)
                    
                    ScrollView {
                        VStack(spacing: 20) {
                            // Dosya seçimi
                            FileSelectionCard(
                                fileName: fileSelectionVM.selectedFile?.lastPathComponent,
                                onSelect: selectFile,
                                previewImage: previewImage,
                                isLoading: fileSelectionVM.selectedFile != nil && previewImage == nil
                            )
                            
                            // Çıktı formatı seçimi
                            if let inputExt = fileSelectionVM.selectedFile?.pathExtension.uppercased(),
                               let supportedOutputs = Utilities.supportedFormats[inputExt] {
                                ConversionOptionsCard(
                                    inputFormat: inputExt,
                                    selectedFormat: $selectedConversionType,
                                    supportedFormats: supportedOutputs
                                )
                                
                                // Dönüştürme butonu
                                ConversionButton(
                                    isConverting: conversionVM.isConverting,
                                    progress: conversionVM.conversionProgress,
                                    action: convertFile
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .frame(minWidth: 450, maxWidth: 650, minHeight: 500)
            
            // Sağ taraf - Son dönüşümler
            RecentConversionsView(
                recentConversions: recentConversionsManager.recentConversions,
                onItemSelected: { record in
                    recentConversionsManager.openPDF(record.fileURL)
                },
                recentConversionsManager: recentConversionsManager
            )
            .frame(minWidth: 250)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showSettings = true
                }) {
                    Label("Ayarlar", systemImage: "gear")
                }
                .help("Sistem ayarları ve kurulu bileşenler")
            }
        }
        .alert(isPresented: $conversionVM.showError) {
            Alert(
                title: Text("Hata"),
                message: Text(conversionVM.errorMessage ?? "Bilinmeyen bir hata oluştu"),
                dismissButton: .default(Text("Tamam"))
            )
        }
        .sheet(isPresented: $conversionVM.showConversionSuccess) {
            ConversionSuccessView(fileURL: conversionVM.convertedFileURL)
        }
        .sheet(isPresented: $showSettings) {
            settingsView
        }
        .onAppear {
            checkInstalledSoftware()
        }
        .onChange(of: fileSelectionVM.selectedFile) { oldValue, newValue in
            previewImage = nil
            updatePreviewImage()
        }
    }
    
    private func selectFile() {
        fileSelectionVM.selectFile(fileTypes: Utilities.supportedExtensions)
    }
    
    private func updatePreviewImage() {
        Utilities.generatePreviewImageAsync(for: fileSelectionVM.selectedFile) { image in
            self.previewImage = image
        }
    }
    
    private func convertFile() {
        guard let inputURL = fileSelectionVM.selectedFile else { return }
        
        conversionVM.convertFile(inputURL: inputURL, outputFormat: selectedConversionType.lowercased()) { success, outputURL in
            if success, let url = outputURL {
                recentConversionsManager.addConversion(
                    fileName: url.lastPathComponent,
                    fileURL: url
                )
            }
        }
    }
    
    // Sistem kurulu bileşenleri kontrol et
    private func checkInstalledSoftware() {
        let installedSoftware = Utilities.checkInstalledSoftware()
        hasTesseract = installedSoftware.tesseract
        hasImageMagick = installedSoftware.imagemagick
        hasLibreOffice = installedSoftware.libreoffice
    }
    
    // Ayarlar ekranı görünümü
    private var settingsView: some View {
        SettingsView(installInfo: InstallationInfo(libreOfficeInstalled: hasLibreOffice, tesseractInstalled: hasTesseract, imageMagickInstalled: hasImageMagick))
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var installInfo = InstallationInfo()
    
    var body: some View {
        VStack(spacing: 25) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sistem Bileşenleri")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Dönüştürme işlemleri için gerekli bileşenler")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            
            // Bileşen durum kartları
            HStack(spacing: 20) {
                // LibreOffice
                ComponentStatusCard(
                    title: "LibreOffice",
                    description: "Office dosyalarını dönüştürmek için gerekli",
                    isInstalled: installInfo.libreOfficeInstalled,
                    iconName: "doc.fill",
                    accentColor: .blue
                )
                
                // Tesseract OCR
                ComponentStatusCard(
                    title: "Tesseract OCR",
                    description: "Metin tanıma işlemleri için gerekli",
                    isInstalled: installInfo.tesseractInstalled,
                    iconName: "text.viewfinder",
                    accentColor: .purple
                )
                
                // ImageMagick
                ComponentStatusCard(
                    title: "ImageMagick",
                    description: "Görsel işleme için gerekli",
                    isInstalled: installInfo.imageMagickInstalled,
                    iconName: "wand.and.stars",
                    accentColor: .orange
                )
            }
            .padding(.horizontal)
            
            if !installInfo.allInstalled {
                // Uyarı banner
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Eksik bileşenler bazı dönüştürme işlemlerini etkileyebilir")
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // Kurulum komutları
                VStack(alignment: .leading, spacing: 16) {
                    Text("Kurulum Komutları")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    if !installInfo.libreOfficeInstalled {
                        InstallCommandView(
                            title: "LibreOffice",
                            command: "brew install --cask libreoffice",
                            iconName: "doc.fill",
                            color: .blue
                        )
                    }
                    
                    if !installInfo.tesseractInstalled {
                        InstallCommandView(
                            title: "Tesseract OCR",
                            command: "brew install tesseract tesseract-lang",
                            iconName: "text.viewfinder",
                            color: .purple
                        )
                    }
                    
                    if !installInfo.imageMagickInstalled {
                        InstallCommandView(
                            title: "ImageMagick",
                            command: "brew install imagemagick",
                            iconName: "wand.and.stars",
                            color: .orange
                        )
                    }
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .frame(width: 750, height: 500)
        .padding(.vertical)
        .background(Color(.windowBackgroundColor))
    }
}

struct ComponentStatusCard: View {
    let title: String
    let description: String
    let isInstalled: Bool
    let iconName: String
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // İkon ve durum
            HStack {
                Image(systemName: iconName)
                    .font(.system(size: 24))
                    .foregroundColor(isInstalled ? .white : accentColor)
                    .frame(width: 48, height: 48)
                    .background(isInstalled ? accentColor : accentColor.opacity(0.1))
                    .cornerRadius(12)
                
                Spacer()
                
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isInstalled ? .green : .red)
            }
            
            // Başlık ve açıklama
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Durum etiketi
            Text(isInstalled ? "Kurulu" : "Kurulu Değil")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isInstalled ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .foregroundColor(isInstalled ? .green : .red)
                .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
}

struct InstallCommandView: View {
    let title: String
    let command: String
    let iconName: String
    let color: Color
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(color)
                Text(title)
                    .fontWeight(.medium)
            }
            
            HStack {
                Text(command)
                    .font(.system(.subheadline, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(6)
                
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isCopied = false
                    }
                }) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .foregroundColor(isCopied ? .green : .secondary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Kurulum bilgilerini izleyen sınıf
class InstallationInfo: ObservableObject {
    @Published var libreOfficeInstalled: Bool
    @Published var tesseractInstalled: Bool
    @Published var imageMagickInstalled: Bool
    
    var allInstalled: Bool {
        return libreOfficeInstalled && tesseractInstalled && imageMagickInstalled
    }
    
    init(libreOfficeInstalled: Bool = false, tesseractInstalled: Bool = false, imageMagickInstalled: Bool = false) {
        self.libreOfficeInstalled = libreOfficeInstalled
        self.tesseractInstalled = tesseractInstalled
        self.imageMagickInstalled = imageMagickInstalled
    }
}

// Son dönüşümler için view
struct RecentConversionsView: View {
    let recentConversions: [ConversionRecord]
    let onItemSelected: (ConversionRecord) -> Void
    let recentConversionsManager: RecentConversionsManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundColor(.blue)
                Text("Son Dönüşümler")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            
            if recentConversions.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)
                    Text("Henüz dönüşüm yapılmadı")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(recentConversions) { record in
                        Button(action: { onItemSelected(record) }) {
                            HStack {
                                // Dosya tipi ikonu
                                Image(systemName: "doc.fill")
                                    .foregroundColor(record.fileType == "PDF" ? .red : .blue)
                                    .font(.title3)
                                
                                // Dosya bilgileri
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.fileName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    
                                    HStack {
                                        Text(record.date, style: .time)
                                        Text("•")
                                        Text(formatFileSize(record.fileSize))
                                        Text("•")
                                        Text(record.fileType)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Açma butonu
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive, action: {
                                recentConversionsManager.removeConversion(record)
                            }) {
                                Label("Listeden Kaldır", systemImage: "trash")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .background(Color(.windowBackgroundColor))
    }
    
    private func formatFileSize(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// Ana içerik için view yapıları
struct FileSelectionCard: View {
    let fileName: String?
    let onSelect: () -> Void
    let previewImage: NSImage?
    let isLoading: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Dosya seçim başlığı
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dosya Seçimi")
                        .font(.headline)
                    Text("Dönüştürmek istediğiniz dosyayı seçin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Dosya seçim butonu
            Button(action: onSelect) {
                HStack {
                    Image(systemName: fileName == nil ? "doc.badge.plus" : "doc.fill")
                        .font(.title2)
                        .foregroundColor(fileName == nil ? .blue : .white)
                    
                    Text(fileName ?? "Dosya Seçin")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    if fileName != nil {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(.white)
                    }
                }
                .padding()
                .background(fileName == nil ? Color.blue.opacity(0.1) : Color.blue)
                .foregroundColor(fileName == nil ? .blue : .white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            
            // Önizleme
            if let image = previewImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 200)
                    .cornerRadius(12)
                    .shadow(radius: 2)
            } else if isLoading {
                ProgressView()
                    .frame(maxHeight: 200)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
}

struct ConversionOptionsCard: View {
    let inputFormat: String
    @Binding var selectedFormat: String
    let supportedFormats: [String]
    
    var body: some View {
        VStack(spacing: 16) {
            // Başlık
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Çıktı Formatı")
                        .font(.headline)
                    Text("Dönüştürme formatını seçin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            // Format seçici
            Picker("Format", selection: $selectedFormat) {
                ForEach(supportedFormats, id: \.self) { format in
                    Text(format).tag(format)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            
            // Dönüşüm gösterimi
            HStack {
                Label {
                    Text(inputFormat)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                }
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Label {
                    Text(selectedFormat)
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.red)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
}

struct ConversionButton: View {
    let isConverting: Bool
    let progress: Double
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            Button(action: action) {
                HStack {
                    Spacer()
                    if isConverting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.trailing, 8)
                        Text("Dönüştürülüyor...")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.title3)
                            .padding(.trailing, 8)
                        Text("Dönüştür")
                            .fontWeight(.semibold)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .background(isConverting ? Color.blue.opacity(0.7) : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(isConverting)
            
            if isConverting {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle())
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
}
