import Testing
@testable import ClipdeckCore

@Suite struct PanelKeyConflictTests {
    private let cmd: UInt = 1_048_576
    private let shift: UInt = 131_072
    private let option: UInt = 524_288

    @Test func 기본_키는_충돌하지_않는다() {
        let b = PanelKeyBindings()
        #expect(b.conflict(for: .plainText, proposing: b.plainText) == nil)
        #expect(b.conflict(for: .nextBoard, proposing: b.nextBoard) == nil)
        #expect(b.conflict(for: .previousBoard, proposing: b.previousBoard) == nil)
    }

    @Test func 고정_키와_겹치면_동작_이름을_알려_준다() {
        let b = PanelKeyBindings()
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 36, modifiers: 0))?.contains("붙여넣기") == true)
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 53, modifiers: 0))?.contains("닫기") == true)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 125, modifiers: 0)) != nil)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 51, modifiers: 0))?.contains("삭제") == true)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 18, modifiers: cmd))?.contains("바로") == true)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 8, modifiers: cmd))?.contains("복사") == true)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 35, modifiers: cmd))?.contains("고정") == true)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 4, modifiers: cmd))?.contains("MCP") == true)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 15, modifiers: cmd))?.contains("미리보기") == true)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 43, modifiers: cmd))?.contains("설정") == true)
    }

    @Test func 수정키가_다르면_고정_키와_겹치지_않는다() {
        let b = PanelKeyBindings()
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 36, modifiers: shift)) == nil)
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 36, modifiers: cmd)) == nil)
    }

    @Test func 다른_패널_키와_겹치면_알려_준다() {
        let b = PanelKeyBindings()
        // 다음 보드 자리에 이전 보드 키(⇧⇥)를 넣는다
        let msg = b.conflict(for: .nextBoard, proposing: b.previousBoard)
        #expect(msg?.contains("이전 보드") == true)
        #expect(b.conflict(for: .plainText, proposing: b.nextBoard)?.contains("다음 보드") == true)
    }

    @Test func 글자_키는_수정키가_있어야_한다() {
        let b = PanelKeyBindings()
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 0, modifiers: 0)) != nil)
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 0, modifiers: shift)) != nil)
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 0, modifiers: option)) == nil)
        // 글자가 아닌 키(F키)는 수정키 없이도 된다
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 122, modifiers: 0)) == nil)
    }

    @Test func 전역_단축키와_같은_조합은_거부한다() {
        let b = PanelKeyBindings()
        let global = HotKeySpec.openPanel // ⇧⌘V
        let same = KeyChord(keyCode: 9, modifiers: cmd | shift)
        #expect(b.conflict(for: .plainText, proposing: same, globalHotKey: global)?.contains("패널 열기") == true)
        #expect(b.conflict(for: .plainText, proposing: same) == nil)
        #expect(b.conflict(for: .plainText, proposing: KeyChord(keyCode: 9, modifiers: cmd | option), globalHotKey: global) == nil)
    }

    @Test func 전역_단축키가_패널_키와_같으면_슬롯을_알려_준다() {
        let b = PanelKeyBindings()
        #expect(b.slot(using: HotKeySpec(keyCode: 48, eventModifiers: 0)) == .nextBoard)
        #expect(b.slot(using: HotKeySpec(keyCode: 36, eventModifiers: shift)) == .plainText)
        #expect(b.slot(using: .openPanel) == nil)
    }

    @Test func 좌우_화살표는_검색창_커서_이동과_겹친다() {
        let b = PanelKeyBindings()
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 123, modifiers: 0)) != nil)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 124, modifiers: 0)) != nil)
        #expect(b.conflict(for: .nextBoard, proposing: KeyChord(keyCode: 124, modifiers: option)) == nil)
    }

    @Test func 전역_단축키는_패널_고정_키와_같으면_동작_이름을_알려_준다() {
        func spec(_ code: UInt16, _ mods: UInt) -> HotKeySpec { HotKeySpec(keyCode: code, eventModifiers: mods) }
        #expect(PanelKeyBindings.fixedKeyConflict(for: spec(35, cmd))?.contains("고정") == true)   // ⌘P
        #expect(PanelKeyBindings.fixedKeyConflict(for: spec(4, cmd))?.contains("MCP") == true)     // ⌘H
        #expect(PanelKeyBindings.fixedKeyConflict(for: spec(43, cmd))?.contains("설정") == true)    // ⌘,
        #expect(PanelKeyBindings.fixedKeyConflict(for: spec(18, cmd))?.contains("바로") == true)    // ⌘1
        #expect(PanelKeyBindings.fixedKeyConflict(for: spec(13, cmd))?.contains("닫기") == true)    // ⌘W
        #expect(PanelKeyBindings.fixedKeyConflict(for: spec(9, cmd))?.contains("붙여넣기") == true)  // ⌘V
        #expect(PanelKeyBindings.fixedKeyConflict(for: .openPanel) == nil)
        #expect(PanelKeyBindings.fixedKeyConflict(for: spec(35, cmd | option)) == nil)
    }
}
