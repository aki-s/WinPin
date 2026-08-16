import AppKit

final class SettingsWindowController: NSWindowController {
    var onDockPreferenceChanged: ((Bool) -> Void)?

    private let showDockCheckbox = NSButton(checkboxWithTitle: "Show Dock icon", target: nil, action: nil)
    private let explanationLabel = NSTextField(labelWithString: "When enabled, WinPin appears in the Dock and Cmd+Tab switcher. When disabled, use the menu bar item or recovery launch to reopen settings.")

    init() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        let window = NSWindow(
            contentRect: contentView.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WinPin Settings"
        window.contentView = contentView
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        setupContentView(contentView)
        syncFromPreferences()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        syncFromPreferences()
        super.showWindow(sender)
        window?.center()
    }

    private func setupContentView(_ contentView: NSView) {
        showDockCheckbox.target = self
        showDockCheckbox.action = #selector(toggleDockIcon)
        showDockCheckbox.translatesAutoresizingMaskIntoConstraints = false

        explanationLabel.translatesAutoresizingMaskIntoConstraints = false
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.maximumNumberOfLines = 0
        explanationLabel.textColor = .secondaryLabelColor

        contentView.addSubview(showDockCheckbox)
        contentView.addSubview(explanationLabel)

        NSLayoutConstraint.activate([
            showDockCheckbox.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            showDockCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            showDockCheckbox.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -24),

            explanationLabel.topAnchor.constraint(equalTo: showDockCheckbox.bottomAnchor, constant: 12),
            explanationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            explanationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
        ])
    }

    private func syncFromPreferences() {
        showDockCheckbox.state = AppPreferences.showDockIcon ? .on : .off
    }

    @objc private func toggleDockIcon() {
        onDockPreferenceChanged?(showDockCheckbox.state == .on)
    }
}
