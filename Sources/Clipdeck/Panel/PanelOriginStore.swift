import AppKit

/// 화면(디스플레이)별로 패널 위치를 기억한다. UserDefaults `panelOrigins`: 화면 번호 문자열 -> "x,y".
/// 설정 JSON(AppSettings)과는 별도 키다.
enum PanelOriginStore {
    static let key = "panelOrigins"

    static func screenID(_ screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }

    static func load(for screen: NSScreen, defaults: UserDefaults = .standard) -> CGPoint? {
        guard let id = screenID(screen),
              let text = defaults.dictionary(forKey: key)?[id] as? String else { return nil }
        let parts = text.split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
    }

    static func save(_ origin: CGPoint, for screen: NSScreen, defaults: UserDefaults = .standard) {
        guard let id = screenID(screen) else { return }
        var all = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        all[id] = "\(origin.x),\(origin.y)"
        defaults.set(all, forKey: key)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
