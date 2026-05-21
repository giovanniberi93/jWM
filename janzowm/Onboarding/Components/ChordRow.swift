import SwiftUI

/// Hero chord row — a sequence of keycaps separated by `+` glyphs.
struct ChordRow: View {
    struct Cap: Identifiable {
        let id = UUID()
        let glyph: String
        let sublabel: String?
        let pulsing: Bool

        init(_ glyph: String, sublabel: String? = nil, pulsing: Bool = false) {
            self.glyph = glyph
            self.sublabel = sublabel
            self.pulsing = pulsing
        }
    }

    let caps: [Cap]

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(caps.enumerated()), id: \.element.id) { idx, cap in
                if idx > 0 { PlusSeparator() }
                TutorialKeycap(cap.glyph, sublabel: cap.sublabel, size: .hero, pulsing: cap.pulsing)
            }
        }
    }
}
