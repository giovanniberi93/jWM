#!/usr/bin/env swift
import AppKit

// Fullscreen countdown banner used by test-integration.sh to make the
// "starting in N…" warning impossible to miss before the suite grabs focus.
// Modeled on SnapOverlayWindow: borderless, transparent, accent-tinted, mouse-
// ignoring. One window per screen, covering the whole frame (not just
// visibleFrame) so it overpaints the menu bar too. Exits after the countdown.
//
// Usage: countdown-overlay <seconds>

let args = CommandLine.arguments
guard args.count >= 2, let total = Int(args[1]), total > 0 else {
    FileHandle.standardError.write(Data("usage: countdown-overlay <seconds>\n".utf8))
    exit(2)
}

final class Delegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var labels: [NSTextField] = []
    private var remaining: Int

    init(seconds: Int) { self.remaining = seconds }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for screen in NSScreen.screens {
            let w = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.setFrame(screen.frame, display: false)

            let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor

            let label = NSTextField(labelWithString: text(for: remaining))
            label.font = .systemFont(ofSize: min(screen.frame.width, screen.frame.height) * 0.10, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])

            w.contentView = content
            w.orderFrontRegardless()
            windows.append(w)
            labels.append(label)
        }

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            self.remaining -= 1
            if self.remaining <= 0 {
                t.invalidate()
                NSApp.terminate(nil)
                return
            }
            let s = self.text(for: self.remaining)
            for label in self.labels { label.stringValue = s }
        }
    }

    private func text(for n: Int) -> String {
        "janzoWM integration tests\nstarting in \(n)…"
    }
}

let app = NSApplication.shared
let delegate = Delegate(seconds: total)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
