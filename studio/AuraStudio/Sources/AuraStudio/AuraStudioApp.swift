import SwiftUI

@main
struct AuraStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}
