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
                self.showErrorMessage("\"\(inputURL.lastPathComponent)\" dosyı zaten \(outputFormat.uppercased()) formatında. Farklı bir format seçin.")
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
                        
                        // Ses bildirimi çal
                        SoundHelper.shared.playConversionCompleteSound()
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
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill.badge.plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.blue)
                    Text("app_name".localized)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
                
                Spacer()
            }
            .padding(.horizontal)
            
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
                    Text("drop_area_hint".localized)
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
                    title: Text("error".localized),
                    message: Text(batchManager.errorMessage ?? "unknown_error".localized),
                    dismissButton: .default(Text("ok".localized))
                )
            }
            
            // Format seçici
            VStack(alignment: .leading, spacing: 8) {
                // Başlık
                VStack(alignment: .leading, spacing: 4) {
                    Text("output_format".localized)
                        .font(.headline)
                    Text("select_conversion_format".localized)
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
                                Text("conversion_in_progress".localized)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                Text("start_batch".localized)
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
                Text("duplicate_file_title".localized)
                    .font(.system(size: 20, weight: .semibold))
                
                Text(String(format: "duplicate_file_message".localized, fileName))
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
                    
                    Text("existing".localized)
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
                    
                    Text("new".localized)
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
                    Text("ok".localized)
                        .fontWeight(.medium)
                        .frame(width: 120)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Button(action: onDismiss) {
                    Text("cancel".localized)
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
                    Label("waiting".localized, systemImage: "clock.fill")
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
                    Label("completed".localized, systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .failed:
                    Label("failed".localized, systemImage: "xmark.circle.fill")
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
                Label("goto_source_location".localized, systemImage: "folder")
            }
            
            Button(action: {
                NSWorkspace.shared.open(job.fileURL)
            }) {
                Label("open_source_file".localized, systemImage: "doc.text.magnifyingglass")
            }
            
            if job.status != .converting {
                Divider()
                
                Button(role: .destructive, action: onRemove) {
                    Label("remove_from_list".localized, systemImage: "trash")
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
    @State private var showAppSettings = false
    @State private var showRequirements = false
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var showRestartAlert = false
    
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
                    HStack {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.fill.badge.plus")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.blue)
                            Text("app_name".localized)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                        
                        Spacer()
                        
                    }
                    .padding(.horizontal)
                    
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
            // Özel NavBar eklemek için toolbar özelliğini kaldıralım
            .safeAreaInset(edge: .top) {
                HStack(spacing: 16) {
                    // Requirements button
                    Button(action: {
                        withAnimation {
                            showRequirements.toggle()
                        }
                    }) {
                        Label("requirements".localized, systemImage: "wrench.and.screwdriver")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Divider()
                        .frame(height: 16)
                    
                    // Language menu
                    Menu {
                        ForEach(LanguageOption.allCases, id: \.self) { language in
                            Button(action: {
                                LanguageManager.shared.setLanguage(language)
                                showRestartAlert = LanguageManager.shared.showRestartAlert
                            }) {
                                HStack {
                                    Text(language.flagEmoji)
                                        .font(.system(size: 16))
                                    Text(language.displayName)
                                        .frame(minWidth: 120, alignment: .leading)
                                    Spacer()
                                    if language == LanguageManager.shared.currentLanguage {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "globe")
                                .font(.system(size: 12))
                            Text("language".localized)
                                .font(.system(size: 12))
                            Text(LanguageManager.shared.currentLanguage.flagEmoji)
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                    }
                    .menuStyle(DefaultMenuStyle())
                    .fixedSize()
                    
                    Divider()
                        .frame(height: 16)
                    
                    // Settings button
                    Button(action: {
                        withAnimation {
                            showAppSettings.toggle()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gear")
                                .font(.system(size: 12))
                            Text("settings".localized)
                                .font(.system(size: 12))
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.05))
            }
            
            // Sağ taraf - Son dönüşümler
            RecentConversionsView(
                recentConversions: recentConversionsManager.recentConversions,
                onItemSelected: { record in
                    recentConversionsManager.openPDF(record.fileURL)
                },
                recentConversionsManager: recentConversionsManager
            )
            .frame(minWidth: 250)
            .navigationTitle("")
        }
        .navigationViewStyle(DoubleColumnNavigationViewStyle())
            .alert(isPresented: $conversionVM.showError) {
                Alert(
                    title: Text("error".localized),
                    message: Text(conversionVM.errorMessage ?? "unknown_error".localized),
                    dismissButton: .default(Text("ok".localized))
                )
            }
            .sheet(isPresented: $conversionVM.showConversionSuccess) {
                ConversionSuccessView(fileURL: conversionVM.convertedFileURL)
            }
            .sheet(isPresented: $showAppSettings) {
                AppSettingsView()
            }
            .alert(isPresented: $showRestartAlert) {
                Alert(
                    title: Text("restart_required_title".localized),
                    message: Text("restart_required_message".localized),
                    primaryButton: .default(Text("restart_now".localized)) {
                        languageManager.confirmLanguageChange()
                    },
                    secondaryButton: .cancel(Text("cancel".localized)) {
                        languageManager.cancelLanguageChange()
                    }
                )
            }
            .onAppear {
                checkInstalledSoftware()
            }
        // Sheets and alerts
        .sheet(isPresented: $showRequirements) {
            RequirementsView()
                .frame(minWidth: 700, minHeight: 500)
        }
    }
    
    private func checkInstalledSoftware() {
        let installedSoftware = Utilities.checkInstalledSoftware()
        hasTesseract = installedSoftware.tesseract
        hasImageMagick = installedSoftware.imagemagick
        hasLibreOffice = installedSoftware.libreoffice
    }
}

// Gereksinimler görünümü
struct RequirementsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab = 0
    @StateObject private var installInfo = InstallationInfo()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("req_title".localized)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("req_description".localized)
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
            .padding()
            .background(Color(.windowBackgroundColor))
            
            // Tab Seçici
            HStack(spacing: 0) {
                ForEach(["status".localized, "installation".localized], id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab == "status".localized ? 0 : 1
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(tab)
                                .font(.headline)
                                .foregroundColor(selectedTab == (tab == "status".localized ? 0 : 1) ? .primary : .secondary)
                            
                            Rectangle()
                                .fill(selectedTab == (tab == "status".localized ? 0 : 1) ? Color.blue : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            
            // İçerik
            TabView(selection: $selectedTab) {
                // Tab 1: Durum
                ScrollView {
                    VStack(spacing: 20) {
                        // Genel durum
                        VStack(alignment: .leading, spacing: 16) {
                            Text("general_status".localized)
                                .font(.headline)
                            
                            HStack(spacing: 20) {
                                VStack(spacing: 12) {
                                    Circle()
                                        .fill(installInfo.allInstalled ? Color.green : Color.red)
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            Image(systemName: installInfo.allInstalled ? "checkmark" : "xmark")
                                                .font(.system(size: 30, weight: .bold))
                                                .foregroundColor(.white)
                                        )
                                    
                                    Text(installInfo.allInstalled ? "ready".localized : "missing_component".localized)
                                        .font(.caption)
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(installInfo.allInstalled ? .green : .red)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    let installedCount = (installInfo.libreOfficeInstalled ? 1 : 0) + 
                                                        (installInfo.tesseractInstalled ? 1 : 0) + 
                                                        (installInfo.imageMagickInstalled ? 1 : 0)
                                    Text("\(installedCount)/3")
                                        .font(.system(size: 36, weight: .bold))
                                        .foregroundColor(installInfo.allInstalled ? .green : .red)
                                    
                                    Text(installInfo.allInstalled ? "installed_components".localized : "missing_component".localized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(16)
                        }
                        
                        // Bileşen durumları
                        Text("components".localized)
                            .font(.headline)
                        
                        ComponentStatusCard(
                            title: "LibreOffice",
                            description: "Office dosyaları için gerekli",
                            isInstalled: installInfo.libreOfficeInstalled,
                            iconName: "doc.fill",
                            accentColor: .blue
                        )
                        
                        ComponentStatusCard(
                            title: "Tesseract OCR",
                            description: "Metin tanıma işlemleri için gerekli",
                            isInstalled: installInfo.tesseractInstalled,
                            iconName: "text.viewfinder",
                            accentColor: .purple
                        )
                        
                        ComponentStatusCard(
                            title: "ImageMagick",
                            description: "Görsel işleme için gerekli",
                            isInstalled: installInfo.imageMagickInstalled, 
                            iconName: "wand.and.stars",
                            accentColor: .orange
                        )
                        
                        // Yardım Kartı
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.blue)
                                    .frame(width: 48, height: 48)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(12)
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("how_to_install".localized)
                                    .font(.headline)
                                Text("installation_instruction_info".localized)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            
                            Button(action: {
                                withAnimation {
                                    selectedTab = 1
                                }
                            }) {
                                Text("goto_installation_page".localized)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(16)
                    }
                    .padding()
                }
                .tag(0)
                
                // Tab 2: Kurulum
                ScrollView {
                    VStack(spacing: 20) {
                        // Kurulum adımları listesi
                        VStack(alignment: .leading, spacing: 16) {
                            Text("installation_steps".localized)
                                .font(.headline)
                            
                            VStack(spacing: 0) {
                                ForEach(["Homebrew", "LibreOffice", "Tesseract OCR", "ImageMagick"], id: \.self) { component in
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 8, height: 8)
                                        
                                        Text(component)
                                            .font(.system(.subheadline))
            
            Spacer()
                                        
                                        Text(component == "Homebrew" ? "req_prerequisite".localized : "req_component".localized)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(.textBackgroundColor))
                                            .cornerRadius(4)
                                    }
                                    .padding(.vertical, 12)
                                    
                                    if component != "ImageMagick" {
                                        Divider()
                                    }
                                }
                            }
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(12)
                        }
                        
                        // Homebrew kurulumu
                        InstallationSection(title: "req_homebrew_title".localized, description: "req_homebrew_desc".localized, steps: [
                            InstallationStep(title: "req_homebrew_step1_title".localized, description: "req_homebrew_step1_detail".localized),
                            InstallationStep(title: "req_homebrew_step2_title".localized, description: "req_homebrew_step2_detail".localized, command: "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""),
                            InstallationStep(title: "req_homebrew_step3_title".localized, description: "req_homebrew_step3_detail".localized, command: "brew --version")
                        ])
                        
                        // LibreOffice kurulumu
                        InstallationSection(title: "req_libreoffice_title".localized, description: "req_libreoffice_desc".localized, steps: [
                            InstallationStep(title: "req_libreoffice_step1_title".localized, description: "req_libreoffice_step1_detail".localized, command: "brew install --cask libreoffice"),
                            InstallationStep(title: "req_libreoffice_step2_title".localized, description: "req_libreoffice_step2_detail".localized, command: "soffice --version")
                        ])
                        
                        // Tesseract kurulumu
                        InstallationSection(title: "req_tesseract_title".localized, description: "req_tesseract_desc".localized, steps: [
                            InstallationStep(title: "req_tesseract_step1_title".localized, description: "req_tesseract_step1_detail".localized, command: "brew install tesseract tesseract-lang"),
                            InstallationStep(title: "req_tesseract_step2_title".localized, description: "req_tesseract_step2_detail".localized, command: "tesseract --version")
                        ])
                        
                        // ImageMagick kurulumu
                        InstallationSection(title: "req_imagemagick_title".localized, description: "req_imagemagick_desc".localized, steps: [
                            InstallationStep(title: "req_imagemagick_step1_title".localized, description: "req_imagemagick_step1_detail".localized, command: "brew install imagemagick"),
                            InstallationStep(title: "req_imagemagick_step2_title".localized, description: "req_imagemagick_step2_detail".localized, command: "convert --version")
                        ])
                    }
                    .padding()
                }
                .tag(1)
            }
            .tabViewStyle(.automatic)
        }
        .onAppear {
            // Check installed status
            let installStatus = Utilities.checkInstalledSoftware()
            installInfo.libreOfficeInstalled = installStatus.libreoffice
            installInfo.tesseractInstalled = installStatus.tesseract
            installInfo.imageMagickInstalled = installStatus.imagemagick
        }
    }
}

// Kurulum bölümü gösterimi
struct InstallationSection: View {
    let title: String
    let description: String
    let steps: [InstallationStep]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
            Text(title)
                    .font(.headline)
                Text(description)
                .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 16) {
                ForEach(steps) { step in
                    InstallationStepView(step: step)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(16)
    }
}

// Kurulum adımı gösterimi
struct InstallationStepView: View {
    let step: InstallationStep
    @State private var isCopied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Title and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(step.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(step.description)
                .font(.caption)
                .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Complete status
                if step.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                }
            }
            
            // Command
            if let command = step.command {
                HStack {
            Text(command)
                        .font(.system(.caption, design: .monospaced))
                .padding(8)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                    
                    Spacer()
                    
                    Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                        withAnimation {
                            isCopied = true
                        }
                        
                        // Reset after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                isCopied = false
                            }
                        }
                    }) {
                    HStack {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            Text(isCopied ? "copied".localized : "copy".localized)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isCopied ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// Kurulum adımı
struct InstallationStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let command: String?
    let isCompleted: Bool
    
    init(title: String, description: String, command: String? = nil, isCompleted: Bool = false) {
        self.title = title
        self.description = description
        self.command = command
        self.isCompleted = isCompleted
    }
}

// Bileşen Durum Kartı
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
            Text(isInstalled ? "installed".localized : "not_installed".localized)
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
                Text("recent_conversions".localized)
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal)
            
            if recentConversions.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "doc.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 10)
                    Text("no_conversions_yet".localized)
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
                                            Text("deleted".localized)
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
                                    Label("goto_file_location".localized, systemImage: "folder")
                                }
                                
                                Button(action: {
                                    NSWorkspace.shared.open(record.fileURL)
                                }) {
                                    Label("open_file".localized, systemImage: "doc.text.magnifyingglass")
                                }
                                
                                Divider()
                            }
                            
                            Button(role: .destructive, action: {
                                recentConversionsManager.removeConversion(record)
                            }) {
                                Label("remove_from_list".localized, systemImage: "trash")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
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

