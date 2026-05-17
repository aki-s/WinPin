import AppKit
import ApplicationServices

protocol AccessibilityPermissionManaging {
    var isTrusted: Bool { get }
    func requestPermissionPrompt()
}

final class AccessibilityPermissionManager: AccessibilityPermissionManaging {
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestPermissionPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
