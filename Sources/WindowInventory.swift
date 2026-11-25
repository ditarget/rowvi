import CoreGraphics
import Foundation

enum WindowInventory {
    static func windowsAreConfined(
        _ windowIDs: Set<CGWindowID>,
        to desktops: Set<UInt64>,
        spacesForWindow: (CGWindowID) -> [UInt64]?
    ) -> Bool {
        !windowIDs.isEmpty && windowIDs.allSatisfy { id in
            guard id != kCGNullWindowID, let spaces = spacesForWindow(id), !spaces.isEmpty else { return false }
            return spaces.allSatisfy(desktops.contains)
        }
    }

    static func containsWindow(
        in windows: [[String: Any]],
        ownedBy owner: pid_t,
        on desktop: UInt64,
        spacesForWindow: (CGWindowID) -> [UInt64]
    ) -> Bool {
        windows.contains { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == owner,
                  (window[kCGWindowLayer as String] as? NSNumber)?.int32Value == CGWindowLevelForKey(.normalWindow),
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0,
                  let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value, id != kCGNullWindowID,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width > 1, frame.height > 1 else { return false }
            return spacesForWindow(id) == [desktop]
        }
    }
}
