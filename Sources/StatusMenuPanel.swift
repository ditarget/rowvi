import AppKit
import SwiftUI

@MainActor
final class StatusMenuPanel: NSPanel {
    private var eventMonitors: [Any] = []
    private var spaceObserver: NSObjectProtocol?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllApplications, .canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(_ menu: RowviMenu, anchoredTo button: NSStatusBarButton) {
        let pointer = NSEvent.mouseLocation
        guard let window = button.window,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? window.screen else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let topEdge = CGRect(x: screen.frame.minX, y: screen.frame.maxY - 80, width: screen.frame.width, height: 80)
        let anchor = topEdge.contains(CGPoint(x: buttonFrame.midX, y: buttonFrame.midY)) ? buttonFrame : nil
        let content = NSHostingView(rootView: menu)
        contentView = content
        let size = content.fittingSize
        let bounds = screen.visibleFrame.insetBy(dx: 6, dy: 4)
        let x = min(max((anchor?.midX ?? pointer.x) - size.width / 2, bounds.minX), bounds.maxX - size.width)
        let y = max(bounds.minY, min(anchor?.minY ?? bounds.maxY, bounds.maxY) - size.height)
        setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
        orderFrontRegardless()

        let dismissOnClick: (NSEvent) -> Void = { [weak self] event in
            guard let self, event.window !== self, event.window !== window,
                  !self.frame.contains(NSEvent.mouseLocation),
                  anchor?.contains(NSEvent.mouseLocation) != true else { return }
            self.dismiss()
        }
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: dismissOnClick) {
            eventMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: { event in
            dismissOnClick(event)
            return event
        }) {
            eventMonitors.append(local)
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        orderOut(nil)
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
    }
}
