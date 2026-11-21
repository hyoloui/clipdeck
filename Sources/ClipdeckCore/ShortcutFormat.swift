import Foundation

/// `NSEvent.ModifierFlags.rawValue`와 Carbon 수정 키 비트. Core는 AppKit을 쓰지 않으므로 값을 직접 둔다.
enum ModifierBits {
    static let shift: UInt = 1 << 17
    static let control: UInt = 1 << 18
    static let option: UInt = 1 << 19
    static let command: UInt = 1 << 20
    static let eventMask: UInt = shift | control | option | command

    static let carbonCommand: UInt32 = 256   // cmdKey
    static let carbonShift: UInt32 = 512     // shiftKey
    static let carbonOption: UInt32 = 2048   // optionKey
    static let carbonControl: UInt32 = 4096  // controlKey
}

extension HotKeySpec {
    /// 녹화기가 받은 키 코드와 `NSEvent.ModifierFlags.rawValue`로 만든다. ⌘⌃⌥⇧ 외의 비트는 버린다.
    public init(keyCode: UInt16, eventModifiers: UInt) {
        var carbon: UInt32 = 0
        if eventModifiers & ModifierBits.command != 0 { carbon |= ModifierBits.carbonCommand }
        if eventModifiers & ModifierBits.shift != 0 { carbon |= ModifierBits.carbonShift }
        if eventModifiers & ModifierBits.option != 0 { carbon |= ModifierBits.carbonOption }
        if eventModifiers & ModifierBits.control != 0 { carbon |= ModifierBits.carbonControl }
        self.init(keyCode: UInt32(keyCode), carbonModifiers: carbon)
    }

    /// `NSEvent.ModifierFlags.rawValue` 형태
    public var eventModifiers: UInt {
        var m: UInt = 0
        if carbonModifiers & ModifierBits.carbonCommand != 0 { m |= ModifierBits.command }
        if carbonModifiers & ModifierBits.carbonShift != 0 { m |= ModifierBits.shift }
        if carbonModifiers & ModifierBits.carbonOption != 0 { m |= ModifierBits.option }
        if carbonModifiers & ModifierBits.carbonControl != 0 { m |= ModifierBits.control }
        return m
    }

    /// 전역 단축키는 ⌘·⌃·⌥ 중 하나가 있어야 한다(⇧만으로는 일반 입력과 구분되지 않는다).
    public var hasRequiredModifier: Bool {
        carbonModifiers & (ModifierBits.carbonCommand | ModifierBits.carbonOption | ModifierBits.carbonControl) != 0
    }
}

/// 단축키를 사람이 읽는 문자열("⇧⌘V")로 바꾼다. 키 이름은 ANSI 배열 기준이다.
public enum ShortcutFormat {
    public static func display(_ spec: HotKeySpec) -> String {
        symbols(eventModifiers: spec.eventModifiers) + keyName(UInt16(truncatingIfNeeded: spec.keyCode))
    }

    /// 앱 실행 시 전역 단축키 등록이 실패했을 때(다른 앱이 쓰는 중) 한 번 보여줄 안내
    public static func hotKeyFailureMessage(_ spec: HotKeySpec) -> String {
        "\(display(spec))를 등록하지 못했습니다 · 메뉴바에서 열 수 있습니다"
    }

    public static func display(_ chord: KeyChord) -> String {
        symbols(eventModifiers: chord.modifiers) + keyName(chord.keyCode)
    }

    /// 수정 키 표기 순서는 ⌃⌥⇧⌘
    public static func symbols(eventModifiers m: UInt) -> String {
        (m & ModifierBits.control != 0 ? "⌃" : "") + (m & ModifierBits.option != 0 ? "⌥" : "")
            + (m & ModifierBits.shift != 0 ? "⇧" : "") + (m & ModifierBits.command != 0 ? "⌘" : "")
    }

    public static func keyName(_ keyCode: UInt16) -> String {
        typingKeys[keyCode] ?? otherKeys[keyCode] ?? "키 \(keyCode)"
    }

    /// 누르면 검색창에 글자가 입력되는 키
    public static func isTypingKey(_ keyCode: UInt16) -> Bool { typingKeys[keyCode] != nil }

    private static let typingKeys: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 49: "Space", 50: "`",
    ]

    private static let otherKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
    ]
}
