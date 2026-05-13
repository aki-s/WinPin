import AppKit

enum LaunchMode {
    static var shouldShowDock: Bool {
        CommandLine.arguments.contains("--show-dock")
            || NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
            || AppPreferences.showDockIcon
    }
}
