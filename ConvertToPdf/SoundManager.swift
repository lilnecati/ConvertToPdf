import Foundation
import AVFoundation
import AppKit  // NSSound için gerekli

class SoundManager {
    static let shared = SoundManager()
    
    private var audioPlayers: [URL: AVAudioPlayer] = [:]
    private var isEnabled = true
    
    private init() {
        // Load system sound
        if let soundURL = Bundle.main.url(forResource: "complete", withExtension: "aiff", subdirectory: "Sounds") {
            prepareSound(url: soundURL)
        }
    }
    
    func toggleSounds(enabled: Bool) {
        isEnabled = enabled
    }
    
    func isSoundEnabled() -> Bool {
        return isEnabled
    }
    
    func playCompletionSound() {
        if !isEnabled { return }
        
        if let soundURL = Bundle.main.url(forResource: "complete", withExtension: "aiff", subdirectory: "Sounds") {
            playSound(url: soundURL)
        } else {
            // Fallback to system sound if our custom sound isn't available
            NSSound.beep()
        }
    }
    
    private func prepareSound(url: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayers[url] = player
        } catch {
            print("Could not load sound file: \(error)")
        }
    }
    
    private func playSound(url: URL) {
        if let player = audioPlayers[url] {
            if player.isPlaying {
                player.currentTime = 0
            } else {
                player.play()
            }
        } else {
            // Try to create and play if not prepared before
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                audioPlayers[url] = player
                player.play()
            } catch {
                print("Could not play sound file: \(error)")
                NSSound.beep()  // Fallback to system sound
            }
        }
    }
} 