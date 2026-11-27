import AppKit
import SwiftUI

@MainActor
final class ProfileToast: NSPanel {
    private var dismissal: Task<Void, Never>?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(profile name: String) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        dismissal?.cancel()

        let bounds = screen.visibleFrame
        let message = AppLanguage.load().text("Applied profile “%@”", name)
        let content = NSHostingView(rootView:
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: min(460, bounds.width - 32))
                .fixedSize()
                .background(.regularMaterial, in: .capsule)
        )
        contentView = content
        let size = content.fittingSize
        setFrame(CGRect(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height - 16,
                        width: size.width, height: size.height), display: true)
        orderFrontRegardless()
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])

        dismissal = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            self?.orderOut(nil)
        }
    }
}
