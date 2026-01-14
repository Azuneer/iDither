import SwiftUI

@main
struct iDitherApp: App { 
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Fix for file picker auto-dismissal: Force app activation on launch
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                        if let window = NSApp.windows.first {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
        }
        .windowToolbarStyle(.unified)
    }
}
