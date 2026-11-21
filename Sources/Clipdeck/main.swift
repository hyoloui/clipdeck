import AppKit

// 메뉴바 전용 상주 앱: Dock 아이콘 없음
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
