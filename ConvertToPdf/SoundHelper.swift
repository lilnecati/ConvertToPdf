import Foundation
import SwiftUI

// Bu sınıf dönüştürme işlemi tamamlandığında ses bildirimi çalmak için 
// BatchConversionManager'dan bağımsız bir çözüm sağlar
class SoundHelper {
    static let shared = SoundHelper()
    
    private init() {}
    
    // Dönüştürme tamamlandığında ses çalmak için 
    func playConversionCompleteSound() {
        // Ses bildirimi çal
        SoundManager.shared.playCompletionSound()
    }
} 