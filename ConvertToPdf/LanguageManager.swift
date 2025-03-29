import SwiftUI
import Foundation

// Desteklenen dil seçenekleri
enum LanguageOption: String, CaseIterable {
    case system = "system"
    case turkish = "tr"
    case english = "en"
    
    var displayName: String {
        switch self {
        case .system: return "System Language"
        case .turkish: return "Türkçe (Turkish)"
        case .english: return "English (İngilizce)"
        }
    }
    
    var flagEmoji: String {
        switch self {
        case .system: return "🌐"
        case .turkish: return "🇹🇷"
        case .english: return "🇬🇧"
        }
    }
}

// Dil yönetimi için ana sınıf
class LanguageManager: ObservableObject {
    // Singleton instance
    static let shared = LanguageManager()
    
    // Kullanıcı tercihleri için storage
    @AppStorage("app_language") private var appLanguage: String = LanguageOption.system.rawValue
    
    // Durum değişkenleri
    @Published var currentLanguage: LanguageOption
    @Published var pendingLanguage: LanguageOption?
    @Published var showRestartAlert: Bool = false
    
    private init() {
        // Önce currentLanguage'i default değerle initialize et
        currentLanguage = .system
        
        // Sonra stored property'ler initialize edildikten sonra appLanguage'i kontrol et
        if let language = LanguageOption(rawValue: appLanguage) {
            currentLanguage = language
        } else {
            // Eğer geçersiz bir dil varsa, system değerini kullan ve AppStorage'ı güncelle
            appLanguage = LanguageOption.system.rawValue
        }
    }
    
    // Dil değiştirme işlemini başlat
    func setLanguage(_ language: LanguageOption) {
        // Eğer seçilen dil zaten aktifse, işlem yapma
        if language == currentLanguage {
            return
        }
        
        // Bekleyen dil değişikliğini kaydet
        pendingLanguage = language
        showRestartAlert = true
    }
    
    // Dil değişimini onayla ve uygulamayı yeniden başlat
    func confirmLanguageChange() {
        guard let pendingLanguage = pendingLanguage else { return }
        
        // Dil tercihini kaydet
        appLanguage = pendingLanguage.rawValue
        
        // Uygulama yeniden başlatma işlemi
        restartApplication()
    }
    
    // Dil değişimini iptal et
    func cancelLanguageChange() {
        pendingLanguage = nil
        showRestartAlert = false
    }
    
    // Uygulamayı yeniden başlatma
    private func restartApplication() {
        // Uygulama yolunu al
        let appPath = Bundle.main.bundleURL.path
        
        // Geçici bash script'i oluştur
        let uuid = UUID().uuidString
        let tempScriptPath = NSTemporaryDirectory() + "restart_\(uuid).sh"
        
        // Script içeriği: 1 saniye bekle ve uygulamayı başlat
        let scriptContent = """
        #!/bin/bash
        sleep 1
        open "\(appPath)"
        """
        
        do {
            // Script dosyası oluştur
            try scriptContent.write(toFile: tempScriptPath, atomically: true, encoding: .utf8)
            
            // Script'e execute izni ver
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempScriptPath)
            
            // Script'i çalıştır
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [tempScriptPath]
            try process.run()
            
            // Mevcut uygulamayı kapat
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            print("Uygulama yeniden başlatılamadı: \(error.localizedDescription)")
        }
    }
}

// String lokalizasyonu için extension
extension String {
    var localized: String {
        return Bundle.main.localizedString(forKey: self, value: nil, table: nil)
    }
}

// Bundle extension ile dil spesifik string'lerin yüklenmesi
extension Bundle {
    // Ana Bundle sınıfını genişletiyoruz, self burada Bundle'ı temsil eder
    func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        // Kullanıcının seçtiği dili al
        let languageCode: String
        let manager = LanguageManager.shared
        
        switch manager.currentLanguage {
        case .system:
            // Sistem dilini kullan - macOS 13+ için güncellenmiş API
            if #available(macOS 13.0, *) {
                languageCode = Locale.current.language.languageCode?.identifier ?? "en"
            } else {
                // Eski API
                languageCode = Locale.current.languageCode ?? "en"
            }
        case .turkish, .english:
            languageCode = manager.currentLanguage.rawValue
        }
        
        // Doğru dil bundle'ını bul
        guard let path = self.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            // Eğer bulunamazsa mevcut bundle'ı kullan
            return NSLocalizedString(key, tableName: tableName, bundle: self, value: value ?? "", comment: "")
        }
        
        // Dil bundle'ından string'i yükle
        return NSLocalizedString(key, tableName: tableName, bundle: bundle, value: value ?? "", comment: "")
    }
}

// SwiftUI View extension
extension View {
    func localizedText(_ key: String) -> some View {
        Text(key.localized)
    }
} 