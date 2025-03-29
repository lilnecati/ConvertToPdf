//
//  ConvertToPdfApp.swift
//  ConvertToPdf
//
//  Created by Necati Yıldırım on 27.03.2025.
//

import SwiftUI

@main
struct ConvertToPdfApp: App {
    init() {
        // Metal uyarılarını devre dışı bırak
        UserDefaults.standard.set(false, forKey: "MTL_DEBUG_LAYER_ENABLED")
        UserDefaults.standard.set(false, forKey: "MTL_SHADER_VALIDATION_ENABLED")
    }
    
    var body: some Scene {
        WindowGroup {
            SplashScreen()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(HiddenTitleBarWindowStyle()) // Pencere stilini modernleştir
    }
}