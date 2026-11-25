import Foundation

struct PanelMetrics {
    let width: CGFloat
    let height: CGFloat
    let count: Int

    private var slots: CGFloat { CGFloat(max(4, count)) }
    var inset: CGFloat { min(width * 0.15, min(32, max(14, width * 0.024))) }
    private var usableWidth: CGFloat { max(0, width - inset * 2) }
    var spacing: CGFloat { min(20, width * 0.016, usableWidth / slots * 0.12) }
    var tileWidth: CGFloat {
        min(280, (usableWidth - spacing * (slots - 1)) / slots)
    }
    var previewHeight: CGFloat {
        min(tileWidth * 0.82, height * 0.38)
    }
    var showsLabels: Bool { tileWidth >= 88 }
    var labelSize: CGFloat { min(21, max(12, tileWidth * 0.105)) }
    var actionSize: CGFloat { min(46, max(28, max(width / 26, height * 0.12))) }
    var interfaceFontSize: CGFloat { min(18, max(12, actionSize * 0.4)) }
    var iconSize: CGFloat { min(68, previewHeight * 0.62) }
    var cornerRadius: CGFloat { min(25, tileWidth * 0.13) }
    var editorWidth: CGFloat { min(395, max(286, width * 0.34)) }

    var contentWidth: CGFloat {
        CGFloat(count) * tileWidth + CGFloat(max(0, count - 1)) * spacing + inset * 2
    }
}
