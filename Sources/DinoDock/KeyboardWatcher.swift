import Cocoa
import ApplicationServices
import CoreGraphics
import Carbon.HIToolbox

/// Persisted preference for the "react to typing" feature.
enum KeyboardPrefs {
    private static let key = "DinoDock.reactsToKeys"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Watches the keyboard system-wide and reports the characters being typed, so
/// the pet can echo them in its speech bubble.
///
/// Privacy notes:
/// - This is **opt-in** (off by default) and only ever shows text transiently;
///   nothing is stored or sent anywhere.
/// - While macOS reports *secure input* (password fields, etc.) capture is
///   suppressed, so passwords are never echoed.
/// - A global key monitor only delivers events when the app is trusted for
///   **Accessibility** (see Apple's `addGlobalMonitorForEvents` docs) — the same
///   permission as "Track Dock exactly". The monitor must be (re)created *after*
///   the permission is granted, so the controller starts it once trust is held.
final class KeyboardWatcher {
    /// Called on the main thread with text to append. A single backspace
    /// character (U+0008) means "delete the last character".
    var onText: ((String) -> Void)?

    private var monitor: Any?

    var isRunning: Bool { monitor != nil }

    /// A cross-app key monitor needs BOTH Accessibility and Input Monitoring on
    /// modern macOS, so require both before we consider the feature usable.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var hasPermission: Bool { hasAccessibility && hasInputMonitoring }

    /// Surfaces both system prompts (and registers the app in both lists).
    static func requestPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        _ = CGRequestListenEventAccess()
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }

    private func handle(_ event: NSEvent) {
        // Never echo while the system is in secure-input mode (password fields).
        if IsSecureEventInputEnabled() { return }

        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            onText?("\u{8}")
            return
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab:
            return
        default:
            break
        }

        // `characters` reflects what was actually typed (shift, layout, IME),
        // which is what we want to show in the bubble.
        guard let chars = event.characters, !chars.isEmpty else { return }

        // Keep printable characters (and space); drop control codes.
        var out = ""
        for scalar in chars.unicodeScalars where scalar.value >= 0x20 && scalar.value != 0x7F {
            out.unicodeScalars.append(scalar)
        }
        if !out.isEmpty { onText?(out) }
    }
}
