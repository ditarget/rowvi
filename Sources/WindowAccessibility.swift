import ApplicationServices
import Foundation

extension AXUIElement {
    func read<T>(_ attribute: String, as _: T.Type = T.self) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var children: [AXUIElement] { read(kAXChildrenAttribute) ?? [] }
    var identifier: String? { read(kAXIdentifierAttribute) }

    func set(_ attribute: String, to value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    func press() -> Bool {
        AXUIElementPerformAction(self, kAXPressAction as CFString) == .success
    }

    var frame: CGRect? {
        guard let position: AXValue = read(kAXPositionAttribute),
              let size: AXValue = read(kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    func resize(to frame: CGRect) -> Bool {
        var position = frame.origin
        var size = frame.size
        guard let pointValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let moved = set(kAXPositionAttribute, to: pointValue)
        let resized = set(kAXSizeAttribute, to: sizeValue)
        return moved && resized
    }
}
