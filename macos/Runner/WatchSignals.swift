import AppKit

/// Cheap signals for the proactive watcher (#213): which app/window is in
/// front and whether the screen is locked. No capture, no AX tree walk -
/// designed to be polled at ~1Hz for pennies.
enum WatchSignals {
    /// Frontmost app name + front window title + lock state.
    static func frontmostInfo() -> [String: Any] {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? ""
        var title = ""
        if let pid = app?.processIdentifier {
            // Front window title of the frontmost app via the window list
            // (no Accessibility permission needed for the name of your own
            // windows; other apps' titles need screen-recording permission,
            // which the watcher requires anyway).
            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
                for entry in list {
                    guard let ownerPid = entry[kCGWindowOwnerPID as String] as? Int32,
                          ownerPid == pid,
                          let layer = entry[kCGWindowLayer as String] as? Int,
                          layer == 0 else { continue }
                    title = entry[kCGWindowName as String] as? String ?? ""
                    break
                }
            }
        }
        return ["app": appName, "title": title, "locked": screenIsLocked()]
    }

    /// True while the lock screen is up (#212: never observe the lock screen).
    static func screenIsLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
