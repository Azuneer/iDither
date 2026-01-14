import SwiftUI

@main
struct iDitherApp: App { 
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Style de fenêtre standard macOS
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
