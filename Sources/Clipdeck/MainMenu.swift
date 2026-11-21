import AppKit

/// 접근자 앱이라 화면에는 보이지 않지만, 설정 창 입력란의 편집 키(⌘Z·⌘X·⌘C·⌘V·⌘A)와 ⌘W·⌘Q가
/// 응답자 체인으로 전달되려면 메인 메뉴가 있어야 한다.
@MainActor
enum MainMenu {
    static func install() {
        let main = NSMenu()
        main.addItem(submenuItem("Clipdeck", [
            item("Clipdeck 종료", #selector(NSApplication.terminate(_:)), "q"),
        ]))
        main.addItem(submenuItem("편집", [
            item("실행 취소", Selector(("undo:")), "z"),
            item("다시 실행", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("오려두기", #selector(NSText.cut(_:)), "x"),
            item("복사", #selector(NSText.copy(_:)), "c"),
            item("붙여넣기", #selector(NSText.paste(_:)), "v"),
            item("전체 선택", #selector(NSText.selectAll(_:)), "a"),
        ]))
        let window = submenuItem("윈도우", [
            item("닫기", #selector(NSWindow.performClose(_:)), "w"),
        ])
        main.addItem(window)
        NSApp.mainMenu = main
        NSApp.windowsMenu = window.submenu
    }

    private static func submenuItem(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    private static func item(_ title: String, _ action: Selector, _ key: String,
                             _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        return it
    }
}
