import SwiftUI

struct AppSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("selectedFormat") var selectedFormat: String = "pdf"
    @AppStorage("enableSounds") private var enableSounds: Bool = true
    
    private let formats = ["pdf", "docx", "txt", "rtf", "html"]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Ayarlar")
                    .font(.title)
                    .bold()
                Spacer()
                Button(action: {
                    self.presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 20)
            
            GroupBox(label: 
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Dönüştürme Formatı")
                        }
            ) {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(formats, id: \.self) { format in
                        Text(format.uppercased())
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.top, 10)
            }
            .padding(.bottom, 10)
            
            GroupBox(label: 
                        HStack {
                            Image(systemName: "speaker.wave.2")
                            Text("Ses Bildirimleri")
                        }
            ) {
                Toggle("Dönüştürme tamamlandığında ses çal", isOn: $enableSounds)
                    .padding(.top, 10)
                    .onChange(of: enableSounds) { _, newValue in
                        SoundManager.shared.toggleSounds(enabled: newValue)
                    }
            }
            .padding(.bottom, 10)
            
            Spacer()
            
            Button(action: {
                // Test sound notification
                if enableSounds {
                    SoundManager.shared.playCompletionSound()
                }
            }) {
                Label("Ses Bildirimini Test Et", systemImage: "play.circle")
            }
            .disabled(!enableSounds)
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 350)
        .padding()
        .onAppear {
            SoundManager.shared.toggleSounds(enabled: enableSounds)
        }
    }
} 