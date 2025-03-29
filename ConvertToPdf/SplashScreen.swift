import SwiftUI

struct SplashScreen: View {
    @State private var isActive = false
    @State private var opacity = 0.0
    @State private var scale: CGFloat = 0.8
    @State private var rotation: Double = 0
    @State private var dotOpacities: [Double] = [0.3, 0.3, 0.3]
    @State private var timers: [Timer] = []
    @ObservedObject private var languageManager = LanguageManager.shared
    
    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                Color(.windowBackgroundColor)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 30) {
                    // App Icon ve Animasyon
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 200, height: 200)
                        
                        // AppIcon'u Assets.xcassets'ten yükleme
                        Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 160, height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            .rotationEffect(.degrees(rotation))
                            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    // Uygulama Adı
                    Text("app_name".localized)
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    // Yükleniyor Animasyonu
                    HStack(spacing: 15) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 12, height: 12)
                                .opacity(dotOpacities[index])
                        }
                    }
                    .padding(.top, 20)
                    
                    // Geliştirici Bilgisi
                    VStack(spacing: 8) {
                        Text("app_description".localized)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 10) {
                            // Geliştirici profil resmi
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Text("NY")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.blue)
                                )
                                
                            Text("developer".localized)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.top, 20)
                }
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    // Başlangıç animasyonu
                    withAnimation(.easeOut(duration: 1.2)) {
                        self.opacity = 1.0
                        self.scale = 1.0
                    }
                    
                    // Döndürme animasyonu
                    withAnimation(Animation.easeInOut(duration: 4).repeatForever(autoreverses: false)) {
                        self.rotation = 360
                    }
                    
                    // Nokta animasyonu
                    startLoadingAnimation()
                    
                    // 4 saniye sonra ana ekrana geç
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        // Timerları temizle
                        for timer in timers {
                            timer.invalidate()
                        }
                        
                        withAnimation {
                            self.isActive = true
                        }
                    }
                }
            }
        }
    }
    
    private func startLoadingAnimation() {
        // İlk timer'ları temizle
        for timer in timers {
            timer.invalidate()
        }
        timers.removeAll()
        
        // Her nokta için animasyon zamanlaması farklı olsun
        for i in 0..<3 {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.4)) {
                    // i. noktayı animasyon için ayarla
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.2) {
                        dotOpacities[i] = dotOpacities[i] == 1.0 ? 0.3 : 1.0
                    }
                }
            }
            timers.append(timer)
        }
    }
}

struct SplashScreen_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreen()
    }
} 