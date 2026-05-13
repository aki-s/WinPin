import AppKit

enum AppIconFactory {
    static let symbol = "📌"

    static func makeApplicationIcon(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.72),
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: symbol, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (size - textSize.width) / 2,
            y: (size - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attributedString.draw(in: textRect)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
