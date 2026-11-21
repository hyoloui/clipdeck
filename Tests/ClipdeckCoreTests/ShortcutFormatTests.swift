import Testing
@testable import ClipdeckCore

@Suite struct ShortcutFormatTests {
    // NSEvent.ModifierFlags: shift 131072, control 262144, option 524288, command 1048576
    @Test func 이벤트_수정키를_카본_값으로_바꾼다() {
        #expect(HotKeySpec(keyCode: 9, eventModifiers: 1_048_576 | 131_072) == .openPanel)
        #expect(HotKeySpec(keyCode: 9, eventModifiers: 1_048_576 | 524_288).carbonModifiers == 256 | 2048)
        #expect(HotKeySpec(keyCode: 9, eventModifiers: 262_144).carbonModifiers == 4096)
    }

    @Test func 카본_값을_이벤트_수정키로_되돌린다() {
        #expect(HotKeySpec.openPanel.eventModifiers == 1_048_576 | 131_072)
        let all = HotKeySpec(keyCode: 0, carbonModifiers: 256 | 512 | 2048 | 4096)
        #expect(all.eventModifiers == 131_072 | 262_144 | 524_288 | 1_048_576)
    }

    @Test func 이벤트에_없는_비트는_무시한다() {
        // capsLock(1<<16)·fn(1<<23) 등
        #expect(HotKeySpec(keyCode: 9, eventModifiers: (1 << 16) | (1 << 23) | 1_048_576).carbonModifiers == 256)
    }

    @Test func 전역_단축키는_cmd_ctrl_opt_중_하나가_필요하다() {
        #expect(HotKeySpec.openPanel.hasRequiredModifier)
        #expect(!HotKeySpec(keyCode: 9, carbonModifiers: 512).hasRequiredModifier)
        #expect(!HotKeySpec(keyCode: 9, carbonModifiers: 0).hasRequiredModifier)
        #expect(HotKeySpec(keyCode: 9, carbonModifiers: 4096 | 512).hasRequiredModifier)
    }

    @Test func 표시_문자열() {
        #expect(ShortcutFormat.display(.openPanel) == "⇧⌘V")
        #expect(ShortcutFormat.display(HotKeySpec(keyCode: 9, eventModifiers: 1_048_576 | 524_288)) == "⌥⌘V")
        #expect(ShortcutFormat.display(KeyChord(keyCode: 36, modifiers: 131_072)) == "⇧↩")
        #expect(ShortcutFormat.display(KeyChord(keyCode: 48, modifiers: 0)) == "⇥")
        // 수정키 순서는 ⌃⌥⇧⌘
        #expect(ShortcutFormat.display(KeyChord(keyCode: 0, modifiers: 262_144 | 524_288 | 131_072 | 1_048_576)) == "⌃⌥⇧⌘A")
        #expect(ShortcutFormat.display(KeyChord(keyCode: 200, modifiers: 0)) == "키 200")
    }
}
