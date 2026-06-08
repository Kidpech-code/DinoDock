import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = PetController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Starts immediately with no permission prompt. The Dock width is
        // estimated from preferences; users can opt into exact tracking
        // (Accessibility) from the menu bar.
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}
