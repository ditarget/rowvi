import AppKit
import SwiftUI

struct WindowMaterial: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeNSView(context: Context) -> BackgroundView {
        let view = BackgroundView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        view.reduceTransparency = reduceTransparency
        return view
    }

    func updateNSView(_ view: BackgroundView, context: Context) {
        view.reduceTransparency = reduceTransparency
    }

    final class BackgroundView: NSVisualEffectView {
        var reduceTransparency = false {
            didSet { configureWindow() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        private func configureWindow() {
            guard let window else { return }
            alphaValue = reduceTransparency ? 1 : 0.85
            window.isOpaque = reduceTransparency
            window.backgroundColor = reduceTransparency ? .windowBackgroundColor : .clear
            window.titlebarAppearsTransparent = true
        }
    }
}
