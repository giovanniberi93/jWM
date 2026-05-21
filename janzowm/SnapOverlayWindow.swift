import Cocoa

final class SnapOverlayWindow: NSWindow {
    private let box = NSBox()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .modalPanel
        collectionBehavior = [.transient, .ignoresCycle]
        ignoresMouseEvents = true

        box.boxType = .custom
        box.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
        box.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.5)
        box.borderWidth = 2
        box.cornerRadius = 10
        box.translatesAutoresizingMaskIntoConstraints = false

        contentView = NSView()
        contentView!.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            box.topAnchor.constraint(equalTo: contentView!.topAnchor),
            box.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
        ])
    }

    /// Show the overlay at the given rect (in AppKit screen coordinates, bottom-left origin).
    func show(at rect: NSRect) {
        setFrame(rect, display: true)
        orderFront(nil)
    }

    func hide() {
        orderOut(nil)
    }
}
