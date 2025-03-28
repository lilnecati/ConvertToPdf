import SwiftUI

struct SplashScreen: View {
    @State private var isActive = false
    @State private var opacity = 0.5
    @State private var scale: CGFloat = 0.9
    
    var body: some View {
        if isActive {
            ContentView()
        } else {
            ZStack {
                Color(NSColor.windowBackgroundColor)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    Image("SplashImage")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 600, height: 450)
                }
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 0.7)) {
                        self.opacity = 1.0
                        self.scale = 1.0
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        withAnimation {
                            self.isActive = true
                        }
                    }
                }
            }
        }
    }
}

struct SplashScreen_Previews: PreviewProvider {
    static var previews: some View {
        SplashScreen()
    }
} 