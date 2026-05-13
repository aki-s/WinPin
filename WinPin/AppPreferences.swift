import Foundation

enum AppPreferences {
    private static let showDockIconKey = "showDockIcon"
    private static let showMenuBarItemKey = "showMenuBarItem"

    static var showDockIcon: Bool {
        get {
            UserDefaults.standard.bool(forKey: showDockIconKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showDockIconKey)
        }
    }

    static var showMenuBarItem: Bool {
        get {
            if UserDefaults.standard.object(forKey: showMenuBarItemKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: showMenuBarItemKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showMenuBarItemKey)
        }
    }
}
