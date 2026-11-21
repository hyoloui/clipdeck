import Foundation

/// 설정에서 바꿀 수 있는 패널 안의 키
public enum PanelKeySlot: String, CaseIterable, Sendable {
    case plainText, nextBoard, previousBoard

    public var label: String {
        switch self {
        case .plainText: "일반 텍스트로 붙여넣기"
        case .nextBoard: "다음 보드"
        case .previousBoard: "이전 보드"
        }
    }
}

extension PanelKeyBindings {
    /// 패널이 이미 쓰는 고정 키: (키 코드, 수정자, 동작 이름)
    private static let fixedKeys: [(KeyChord, String)] = {
        var list: [(KeyChord, String)] = [
            (KeyChord(keyCode: 36, modifiers: 0), "붙여넣기"),
            (KeyChord(keyCode: 76, modifiers: 0), "붙여넣기"),
            (KeyChord(keyCode: 53, modifiers: 0), "닫기"),
            (KeyChord(keyCode: 126, modifiers: 0), "위로 이동"),
            (KeyChord(keyCode: 125, modifiers: 0), "아래로 이동"),
            (KeyChord(keyCode: 51, modifiers: 0), "삭제"),
            (KeyChord(keyCode: 123, modifiers: 0), "검색창 커서 이동"),
            (KeyChord(keyCode: 124, modifiers: 0), "검색창 커서 이동"),
            (KeyChord(keyCode: 8, modifiers: ModifierBits.command), "클립보드에만 복사"),
            (KeyChord(keyCode: 35, modifiers: ModifierBits.command), "보드에 고정"),
            (KeyChord(keyCode: 4, modifiers: ModifierBits.command), "MCP 숨김 전환"),
            (KeyChord(keyCode: 15, modifiers: ModifierBits.command), "가려진 항목 미리보기"),
            (KeyChord(keyCode: 43, modifiers: ModifierBits.command), "설정 열기"),
            (KeyChord(keyCode: 13, modifiers: ModifierBits.command), "패널 닫기"),
            (KeyChord(keyCode: 12, modifiers: ModifierBits.command), "종료 방지"),
            // 검색창 편집 키
            (KeyChord(keyCode: 9, modifiers: ModifierBits.command), "검색창 붙여넣기"),
            (KeyChord(keyCode: 0, modifiers: ModifierBits.command), "검색창 전체 선택"),
            (KeyChord(keyCode: 7, modifiers: ModifierBits.command), "검색창 잘라내기"),
            (KeyChord(keyCode: 6, modifiers: ModifierBits.command), "검색창 실행 취소"),
            (KeyChord(keyCode: 6, modifiers: ModifierBits.command | ModifierBits.shift), "검색창 다시 실행"),
        ]
        for code: UInt16 in [18, 19, 20, 21, 23, 22, 26, 28, 25] {
            list.append((KeyChord(keyCode: code, modifiers: ModifierBits.command), "항목 바로 붙여넣기(⌘1–9)"))
        }
        return list
    }()

    /// `slot`에 `chord`를 넣으려 할 때 막아야 하면 이유(한국어)를, 아니면 nil을 돌려준다.
    public func conflict(for slot: PanelKeySlot, proposing chord: KeyChord, globalHotKey: HotKeySpec? = nil) -> String? {
        let mods = chord.modifiers & ModifierBits.eventMask
        let chord = KeyChord(keyCode: chord.keyCode, modifiers: mods)
        let shown = ShortcutFormat.display(chord)

        // 수정키 없는(⇧만 포함) 글자 키는 검색창 입력을 가로챈다
        if ShortcutFormat.isTypingKey(chord.keyCode),
           mods & (ModifierBits.command | ModifierBits.control | ModifierBits.option) == 0 {
            return "\(shown)은(는) 검색어 입력과 겹칩니다. ⌘, ⌃, ⌥ 중 하나를 포함하거나 글자가 아닌 키를 쓰세요."
        }
        if let fixed = Self.fixedKeys.first(where: { $0.0 == chord }) {
            return "\(shown)은(는) 패널의 '\(fixed.1)' 키와 겹칩니다."
        }
        // 전역 단축키가 먼저 가로채므로 같은 조합이면 패널 안에서는 동작하지 않는다
        if let g = globalHotKey, g.keyCode == UInt32(chord.keyCode), g.eventModifiers == chord.modifiers {
            return "\(shown)은(는) 전역 '패널 열기' 단축키와 같습니다."
        }
        for other in PanelKeySlot.allCases where other != slot {
            if self[other] == chord { return "\(shown)은(는) '\(other.label)' 키와 겹칩니다." }
        }
        return nil
    }

    /// 전역 단축키가 패널 고정 키와 같으면 패널 안에서 그 동작이 막히므로 이유를 돌려준다
    public static func fixedKeyConflict(for spec: HotKeySpec) -> String? {
        let chord = KeyChord(keyCode: UInt16(truncatingIfNeeded: spec.keyCode), modifiers: spec.eventModifiers)
        guard let fixed = fixedKeys.first(where: { $0.0 == chord }) else { return nil }
        return "\(ShortcutFormat.display(spec))은(는) 패널의 '\(fixed.1)' 키와 겹칩니다."
    }

    /// 전역 단축키로 `spec`을 쓰려 할 때 같은 조합을 쓰는 패널 키가 있으면 그 슬롯
    public func slot(using spec: HotKeySpec) -> PanelKeySlot? {
        PanelKeySlot.allCases.first {
            let c = self[$0]
            return UInt32(c.keyCode) == spec.keyCode && c.modifiers == spec.eventModifiers
        }
    }

    public subscript(slot: PanelKeySlot) -> KeyChord {
        get {
            switch slot {
            case .plainText: plainText
            case .nextBoard: nextBoard
            case .previousBoard: previousBoard
            }
        }
        set {
            switch slot {
            case .plainText: plainText = newValue
            case .nextBoard: nextBoard = newValue
            case .previousBoard: previousBoard = newValue
            }
        }
    }
}
