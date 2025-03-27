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
    private var fileCheckTimer: Timer?
    
    init() {
        loadSavedConversions()
        startFileExistenceCheck()
    }
    
    deinit {
        fileCheckTimer?.invalidate()
    }
    
    private func startFileExistenceCheck() {
        // Her 2 saniyede bir dosyaların varlığını kontrol et
        fileCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFilesExistence()
        }
    }
    
    private func checkFilesExistence() {
        // Dosyaların varlığını kontrol et ve UI'ı güncelle
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
    
    private func loadSavedConversions() {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ConversionRecord].self, from: data) {
            // Tüm kayıtları yükle ve tarihe göre sırala
            recentConversions = decoded.sorted { $0.date > $1.date }
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
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }
    
    func removeConversion(_ record: ConversionRecord) {
        recentConversions.removeAll { $0.id == record.id }
        saveConversions()
    }
}

// Dönüştürme işi modeli
struct ConversionJob: Identifiable, Equatable {
    let id = UUID()
    let fileURL: URL
    var status: JobStatus = .waiting
    var progress: Double = 0.0
    var outputURL: URL?
    
    enum JobStatus {
        case waiting
        case converting
        case completed
        case failed
    }
}

// Toplu dönüştürme yöneticisi
class BatchConversionManager: ObservableObject {
    @Published var jobs: [ConversionJob] = []
    @Published var isProcessing = false
    @Published var showDuplicateError = false
    @Published var duplicateFileName = ""
    @Published var showReplaceAlert = false
    @Published var replaceFileName = ""
    @Published var replaceFolderName = ""
    @Published var showError = false
    @Published var errorMessage: String?
    var pendingReplaceAction: (() -> Void)?
    private var currentJobIndex = 0
    private let conversionVM = ConversionViewModel()
    private let recentConversionsManager: RecentConversionsManager
    
    init(recentConversionsManager: RecentConversionsManager) {
        self.recentConversionsManager = recentConversionsManager
    }
    
    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true
    }
    
    func addJob(fileURL: URL) {
        // Aynı isimli dosya kontrolü
        let fileName = fileURL.lastPathComponent
        if jobs.contains(where: { $0.fileURL.lastPathComponent == fileName }) {
            duplicateFileName = fileName
            showDuplicateError = true
            return
        }
        jobs.append(ConversionJob(fileURL: fileURL))
    }
    
    func addJobs(fileURLs: [URL]) {
        // Önce tüm dosya isimlerini kontrol et
        let newFileNames = fileURLs.map { $0.lastPathComponent }
        let existingFileNames = jobs.map { $0.fileURL.lastPathComponent }
        
        // Yeni dosyalar arasında tekrar var mı?
        let duplicatesInNew = Set(newFileNames.filter { name in
            newFileNames.filter { $0 == name }.count > 1
        })
        
        // Mevcut dosyalarla çakışma var mı?
        let duplicatesWithExisting = Set(newFileNames.filter { existingFileNames.contains($0) })
        
        // Herhangi bir tekrar varsa
        if let firstDuplicate = duplicatesInNew.first ?? duplicatesWithExisting.first {
            duplicateFileName = firstDuplicate
            showDuplicateError = true
            return
        }
        
        // Tekrar yoksa dosyaları ekle
        fileURLs.forEach { addJob(fileURL: $0) }
    }
    
    private func checkFileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    private func handleFileReplacement(for url: URL, completion: @escaping () -> Void) {
        if checkFileExists(at: url) {
            replaceFileName = url.lastPathComponent
            replaceFolderName = url.deletingLastPathComponent().lastPathComponent
            pendingReplaceAction = completion
            showReplaceAlert = true
        } else {
            completion()
        }
    }
    
    func startProcessing(outputFormat: String, completion: @escaping () -> Void) {
        guard !isProcessing, !jobs.isEmpty else { return }
        
        isProcessing = true
        currentJobIndex = 0
        processNextJob(outputFormat: outputFormat.lowercased(), completion: completion)
    }
    
    private func processNextJob(outputFormat: String, completion: @escaping () -> Void) {
        guard currentJobIndex < jobs.count else {
            isProcessing = false
            completion()
            return
        }
        
        // Mevcut işi güncelle
        jobs[currentJobIndex].status = .converting
        
        let currentJob = jobs[currentJobIndex]
        let inputURL = currentJob.fileURL
        
        // Çıktı dosyasının yolunu oluştur
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension(outputFormat)
        
        // Aynı formata dönüştürme kontrolü
        if inputURL.pathExtension.lowercased() == outputFormat.lowercased() {
            DispatchQueue.main.async {
                self.showErrorMessage("\"\(inputURL.lastPathComponent)\" dosyası zaten \(outputFormat.uppercased()) formatında. Farklı bir format seçin.")
                self.jobs[self.currentJobIndex].status = .failed
                self.currentJobIndex += 1
                self.processNextJob(outputFormat: outputFormat, completion: completion)
            }
            return
        }
        
        // İlerleme güncellemesi için timer
        let progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if self.jobs[self.currentJobIndex].status != .converting {
                timer.invalidate()
                return
            }
            
            DispatchQueue.main.async {
                self.jobs[self.currentJobIndex].progress = self.conversionVM.conversionProgress
            }
        }
        
        // Dosya varsa üzerine yazma kontrolü yap
        handleFileReplacement(for: outputURL) { [weak self] in
            guard let self = self else { return }
            
            // Dönüştürme işlemini başlat
            self.conversionVM.convertFile(inputURL: inputURL, outputFormat: outputFormat) { success, url in
                DispatchQueue.main.async {
                    progressTimer.invalidate()
                    
                    // İş durumunu güncelle
                    if success, let url = url {
                        self.jobs[self.currentJobIndex].status = .completed
                        self.jobs[self.currentJobIndex].progress = 1.0
                        self.jobs[self.currentJobIndex].outputURL = url
                        
                        // Son dönüşümlere ekle
                        self.recentConversionsManager.addConversion(
                            fileName: url.lastPathComponent,
                            fileURL: url
                        )
                    } else {
                        self.jobs[self.currentJobIndex].status = .failed
                    }
                    
                    // Sonraki işe geç
                    self.currentJobIndex += 1
                    self.processNextJob(outputFormat: outputFormat, completion: completion)
                }
            }
        }
    }
    
    func removeJob(at index: Int) {
        guard index < jobs.count else { return }
        jobs.remove(at: index)
    }
    
    func clearCompletedJobs() {
        jobs.removeAll { $0.status == .completed }
    }
    
    func clearAllJobs() {
        jobs.removeAll()
        isProcessing = false
        currentJobIndex = 0
    }
    
    func cancelProcessing() {
        isProcessing = false
        // İşlem yapılan dosyayı failed olarak işaretle
        if currentJobIndex < jobs.count {
            jobs[currentJobIndex].status = .failed
        }
        // Bekleyen işleri waiting durumunda bırak
        currentJobIndex = 0
    }
}

// Sürükle-bırak için NSView tabanlı çözüm
struct DragAndDropView: NSViewRepresentable {
    let onDrop: ([URL]) -> Void
    @Binding var showDuplicateError: Bool
    @Binding var duplicateFileName: String
    
    func makeNSView(context: Context) -> NSView {
        let view = DragDropView()
        view.onDrop = { urls in
            // Dosya isimlerini kontrol et
            let fileNames = urls.map { $0.lastPathComponent }
            let uniqueFileNames = Set(fileNames)
            
            if fileNames.count != uniqueFileNames.count {
                // Tekrarlanan dosya ismini bul
                let duplicates = fileNames.filter { name in
                    fileNames.filter { $0 == name }.count > 1
                }
                if let firstDuplicate = duplicates.first {
                    duplicateFileName = firstDuplicate
                    showDuplicateError = true
                    return
                }
            }
            
            onDrop(urls)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    class DragDropView: NSView {
        var onDrop: (([URL]) -> Void)?
        
        init() {
            super.init(frame: .zero)
            registerForDraggedTypes([.fileURL])
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            return .copy
        }
        
        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else {
                return false
            }
            onDrop?(items)
            return true
        }
    }
}

// Toplu dönüştürme view
struct BatchConversionView: View {
    @ObservedObject var batchManager: BatchConversionManager
    @Binding var selectedFormat: String
    let supportedFormats: [String]
    @State private var showDuplicateError = false
    @State private var duplicateFileName = ""
    
    private var currentInputFormat: String {
        if let currentJob = batchManager.jobs.first(where: { $0.status == .converting }) {
            return currentJob.fileURL.pathExtension.uppercased()
        } else if let firstJob = batchManager.jobs.first {
            return firstJob.fileURL.pathExtension.uppercased()
        }
        return "PDF"
    }
    
    private func checkForDuplicates(in urls: [URL]) -> String? {
        // Yeni dosyaların isimleri
        let newFileNames = urls.map { $0.lastPathComponent }
        let existingFileNames = batchManager.jobs.map { $0.fileURL.lastPathComponent }
        
        // Yeni dosyalar arasında tekrar var mı?
        if let duplicate = newFileNames.first(where: { name in
            newFileNames.filter { $0 == name }.count > 1
        }) {
            return duplicate
        }
        
        // Mevcut dosyalarla çakışma var mı?
        if let duplicate = newFileNames.first(where: { existingFileNames.contains($0) }) {
            return duplicate
        }
        
        return nil
    }
    
    private func handleFileSelection(_ urls: [URL]) {
        if let duplicate = checkForDuplicates(in: urls) {
            duplicateFileName = duplicate
            showDuplicateError = true
        } else {
            batchManager.addJobs(fileURLs: urls)
        }
    }
    
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        let allSupportedFormats = Utilities.supportedExtensions
        panel.allowedContentTypes = allSupportedFormats.compactMap { UTType(filenameExtension: $0.lowercased()) }
        
        if panel.runModal() == .OK {
            let selectedFiles = panel.urls.filter { url in
                let fileExtension = url.pathExtension.uppercased()
                return Utilities.supportedFormats[fileExtension] != nil
            }
            
            if !selectedFiles.isEmpty {
                handleFileSelection(selectedFiles)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Başlık
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dönüştürme")
                        .font(.headline)
                    Text("Birden fazla dosyayı aynı anda dönüştürün")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                // İşlem kontrolleri
                HStack(spacing: 12) {
                    Button(action: { batchManager.clearCompletedJobs() }) {
                        Label("Tamamlananları Temizle", systemImage: "checkmark.circle")
                    }
                    .disabled(batchManager.jobs.filter { $0.status == .completed }.isEmpty)
                    
                    Button(action: { batchManager.clearAllJobs() }) {
                        Label("Tümünü Temizle", systemImage: "trash")
                    }
                    .disabled(batchManager.jobs.isEmpty)
                }
            }
            
            // Dosya bırakma alanı
            DragAndDropView(
                onDrop: handleFileSelection,
                showDuplicateError: $showDuplicateError,
                duplicateFileName: $duplicateFileName
            )
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(Color.blue.opacity(0.05))
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.title)
                        .foregroundColor(.blue)
                    Text("Dosyaları buraya sürükleyin veya tıklayarak seçin")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            )
            .onTapGesture {
                selectFiles()
            }
            .sheet(isPresented: $showDuplicateError) {
                DuplicateFileErrorView(fileName: duplicateFileName) {
                    showDuplicateError = false
                }
            }
            .sheet(isPresented: $batchManager.showReplaceAlert) {
                ReplaceFileView(
                    fileName: batchManager.replaceFileName,
                    folderName: batchManager.replaceFolderName,
                    onReplace: {
                        if let action = batchManager.pendingReplaceAction {
                            action()
                        }
                        batchManager.showReplaceAlert = false
                    },
                    onCancel: {
                        batchManager.showReplaceAlert = false
                    }
                )
            }
            .alert(isPresented: $batchManager.showError) {
                Alert(
                    title: Text("Dönüştürme Hatası"),
                    message: Text(batchManager.errorMessage ?? ""),
                    dismissButton: .default(Text("Tamam"))
                )
            }
            
            // Format seçici
            VStack(alignment: .leading, spacing: 8) {
                // Başlık
                VStack(alignment: .leading, spacing: 4) {
                    Text("Çıktı Formatı")
                        .font(.headline)
                    Text("Dönüştürme formatını seçin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Format seçici
                HStack {
                    Text("Format")
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $selectedFormat) {
                        ForEach(supportedFormats, id: \.self) { format in
                            Text(format).tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(maxWidth: .infinity)
                }
                
                // Dönüşüm gösterimi
                HStack(spacing: 16) {
                    Label {
                        Text(currentInputFormat)
                            .fontWeight(.medium)
                    } icon: {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)
                    }
                    
                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                    
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
            
            // Kuyruk listesi
            if !batchManager.jobs.isEmpty {
                List {
                    ForEach(Array(batchManager.jobs.enumerated()), id: \.element.id) { index, job in
                        JobRowView(job: job, onRemove: {
                            batchManager.removeJob(at: index)
                        })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    batchManager.removeJob(at: index)
                                } label: {
                                    Label("Sil", systemImage: "trash")
                                }
                            }
                    }
                }
                .frame(height: 200)
                .cornerRadius(12)
                
                // Kontrol butonları
                HStack(spacing: 12) {
                    if batchManager.isProcessing {
                        // İptal butonu
                        Button(action: {
                            batchManager.cancelProcessing()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("İptal Et")
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 24)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Dönüştürme butonu
                    Button(action: {
                        batchManager.startProcessing(outputFormat: selectedFormat) {
                            // Tamamlandığında yapılacak işlemler
                        }
                    }) {
                        HStack {
                            if batchManager.isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .padding(.trailing, 8)
                                Text("Dönüştürülüyor...")
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                Text("Toplu Dönüştürmeyi Başlat")
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity)
                        .background(batchManager.isProcessing ? Color.blue.opacity(0.7) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(batchManager.isProcessing || batchManager.jobs.isEmpty)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
}

struct DuplicateFileErrorView: View {
    let fileName: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Hata ikonu
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Circle()
                    .stroke(Color.red.opacity(0.2), lineWidth: 2)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.red)
            }
            .padding(.top, 24)
            
            // Başlık ve mesaj
            VStack(spacing: 16) {
                Text("Aynı İsimli Dosya")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("\"\(fileName)\" isimli dosya zaten mevcut veya birden fazla kez eklenmeye çalışılıyor.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            
            // Dosya detayları
            HStack(spacing: 12) {
                // Sol taraf - Eski dosya
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    Text("Mevcut")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Ok işareti
                Image(systemName: "xmark")
                    .foregroundColor(.red)
                    .font(.system(size: 16, weight: .bold))
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(Circle())
                
                // Sağ taraf - Yeni dosya
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    
                    Text("Yeni")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            .background(Color(.textBackgroundColor))
            .cornerRadius(12)
            
            // Butonlar
            HStack(spacing: 16) {
                Button(action: onDismiss) {
                    Text("Tamam")
                        .fontWeight(.medium)
                        .frame(width: 120)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: onDismiss) {
                    Text("İptal")
                        .fontWeight(.medium)
                        .frame(width: 120)
                        .padding(.vertical, 12)
                        .background(Color(.controlBackgroundColor))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(width: 400, height: 420)
        .background(Color(.windowBackgroundColor))
    }
}

// İş satırı görünümü
struct JobRowView: View {
    let job: ConversionJob
    let onRemove: () -> Void
    
    private func getFileIcon(for url: URL) -> (icon: String, color: Color) {
        let fileExtension = url.pathExtension.uppercased()
        switch fileExtension {
        case "PDF":
            return ("doc.fill", .red)
        case "DOC", "DOCX":
            return ("doc.text.fill", .blue)
        case "XLS", "XLSX":
            return ("tablecells.fill", .green)
        case "PPT", "PPTX":
            return ("chart.bar.doc.horizontal.fill", .orange)
        case "JPG", "JPEG", "PNG":
            return ("photo.fill", .purple)
        default:
            return ("doc.fill", .gray)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Dosya ikonu ve adı
            let fileInfo = getFileIcon(for: job.fileURL)
            Image(systemName: fileInfo.icon)
                .foregroundColor(fileInfo.color)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(job.fileURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(job.fileURL.pathExtension.uppercased())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Durum göstergesi
            Group {
                switch job.status {
                case .waiting:
                    Label("Bekliyor", systemImage: "clock.fill")
                        .foregroundColor(.orange)
                case .converting:
                    HStack(spacing: 8) {
                        ProgressView(value: job.progress)
                            .frame(width: 80)
                        Text("\(Int(job.progress * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                case .completed:
                    Label("Tamamlandı", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Label("Başarısız", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .contextMenu {
            if job.status == .completed, let outputURL = job.outputURL {
                Button(action: {
                    NSWorkspace.shared.selectFile(outputURL.path, inFileViewerRootedAtPath: outputURL.deletingLastPathComponent().path)
                }) {
                    Label("Dosya Konumuna Git", systemImage: "folder")
                }
                
                Button(action: {
                    NSWorkspace.shared.open(outputURL)
                }) {
                    Label("Dosyayı Aç", systemImage: "doc.text.magnifyingglass")
                }
                
                Divider()
            }
            
            Button(action: {
                NSWorkspace.shared.selectFile(job.fileURL.path, inFileViewerRootedAtPath: job.fileURL.deletingLastPathComponent().path)
            }) {
                Label("Kaynak Dosya Konumuna Git", systemImage: "folder")
            }
            
            Button(action: {
                NSWorkspace.shared.open(job.fileURL)
            }) {
                Label("Kaynak Dosyayı Aç", systemImage: "doc.text.magnifyingglass")
            }
            
            if job.status != .converting {
                Divider()
                
                Button(role: .destructive, action: onRemove) {
                    Label("Listeden Kaldır", systemImage: "trash")
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject private var conversionVM = ConversionViewModel()
    @ObservedObject private var fileSelectionVM = FileSelectionViewModel()
    @ObservedObject private var recentConversionsManager = RecentConversionsManager()
    @State private var selectedConversionType: String = "PDF"
    @State private var showSettings = false
    
    // Kurulu bileşenler için state değişkenleri
    @State private var hasImageMagick = false
    @State private var hasTesseract = false
    @State private var hasLibreOffice = false
    
    // Özel renkler
    private let accentColor = Color.blue
    private let backgroundColor = Color(.windowBackgroundColor)
    private let cardBackground = Color(.controlBackgroundColor)
    
    @StateObject private var batchManager: BatchConversionManager
    
    init() {
        let recentManager = RecentConversionsManager()
        _recentConversionsManager = ObservedObject(wrappedValue: recentManager)
        _batchManager = StateObject(wrappedValue: BatchConversionManager(recentConversionsManager: recentManager))
    }
    
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
                    
                    // Toplu dönüştürme kartı
                    BatchConversionView(
                        batchManager: batchManager,
                        selectedFormat: $selectedConversionType,
                        supportedFormats: ["PDF","JPG", "PNG", "PPTX", "XML" ,"DOCX"]
                    )
                    .padding(.horizontal)
                    
                    Spacer()
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
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
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
    }
    
    private func checkInstalledSoftware() {
        let installedSoftware = Utilities.checkInstalledSoftware()
        hasTesseract = installedSoftware.tesseract
        hasImageMagick = installedSoftware.imagemagick
        hasLibreOffice = installedSoftware.libreoffice
    }
    
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
    
    private func fileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
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
                        Button(action: { 
                            if fileExists(at: record.fileURL) {
                                onItemSelected(record)
                            }
                        }) {
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
                                        
                                        if !fileExists(at: record.fileURL) {
                                            Text("•")
                                            Text("Silindi")
                                                .foregroundColor(.red)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Açma butonu
                                if fileExists(at: record.fileURL) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.blue)
                                        .font(.title3)
                                } else {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(.red)
                                        .font(.title3)
                                }
                            }
                            .contentShape(Rectangle())
                            .opacity(fileExists(at: record.fileURL) ? 1.0 : 0.7)
                        }
                        .buttonStyle(.plain)
                        .disabled(!fileExists(at: record.fileURL))
                        .contextMenu {
                            if fileExists(at: record.fileURL) {
                                Button(action: {
                                    NSWorkspace.shared.selectFile(record.fileURL.path, inFileViewerRootedAtPath: record.fileURL.deletingLastPathComponent().path)
                                }) {
                                    Label("Dosya Konumuna Git", systemImage: "folder")
                                }
                                
                                Button(action: {
                                    NSWorkspace.shared.open(record.fileURL)
                                }) {
                                    Label("Dosyayı Aç", systemImage: "doc.text.magnifyingglass")
                                }
                                
                                Divider()
                            }
                            
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

// Dosya değiştirme onay görünümü
struct ReplaceFileView: View {
    let fileName: String
    let folderName: String
    let onReplace: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Uyarı ikonu
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Circle()
                    .stroke(Color.yellow.opacity(0.2), lineWidth: 2)
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.yellow)
            }
            .padding(.top, 24)
            
            // Başlık ve mesaj
            VStack(spacing: 16) {
                Text("\"\(fileName)\" zaten mevcut")
                    .font(.system(size: 20, weight: .semibold))
                
                Text("\"\(folderName)\" klasöründe aynı isimde bir dosya zaten var. Değiştirmek mevcut içeriğin üzerine yazacak.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }
            
            // Dosya detayları
            HStack(spacing: 12) {
                // Sol taraf - Eski dosya
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    Text("Mevcut")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Ok işareti
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.yellow)
                    .font(.system(size: 16, weight: .bold))
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .clipShape(Circle())
                
                // Sağ taraf - Yeni dosya
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow.opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundColor(.yellow)
                    }
                    
                    Text("Yeni")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 32)
            .background(Color(.textBackgroundColor))
            .cornerRadius(12)
            
            // Butonlar
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("İptal")
                        .fontWeight(.medium)
                        .frame(width: 120)
                        .padding(.vertical, 12)
                        .background(Color(.controlBackgroundColor))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                
                Button(action: onReplace) {
                    Text("Değiştir")
                        .fontWeight(.medium)
                        .frame(width: 120)
                        .padding(.vertical, 12)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
            
            Spacer()
        }
        .frame(width: 400, height: 420)
        .background(Color(.windowBackgroundColor))
    }
}
