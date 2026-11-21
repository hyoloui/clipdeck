// 사용: swift scripts/make-icon.swift  → Resources/AppIcon.icns 생성 (겹친 카드 3장)
import AppKit

let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 배경: 둥근 사각형 그라데이션
let bg = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210)
NSGradient(starting: NSColor(red: 0.16, green: 0.20, blue: 0.36, alpha: 1),
           ending: NSColor(red: 0.07, green: 0.09, blue: 0.18, alpha: 1))!.draw(in: bg, angle: -90)

// 카드 3장: 뒤에서 앞으로 기울기와 색을 달리해 겹친다
func card(angle: CGFloat, dx: CGFloat, dy: CGFloat, color: NSColor) {
    let t = NSAffineTransform()
    t.translateX(by: size / 2 + dx, yBy: size / 2 + dy)
    t.rotate(byDegrees: angle)
    let path = NSBezierPath(roundedRect: NSRect(x: -190, y: -250, width: 380, height: 500), xRadius: 48, yRadius: 48)
    path.transform(using: t as AffineTransform)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}
card(angle: 16, dx: 110, dy: 20, color: NSColor(red: 0.36, green: 0.62, blue: 0.95, alpha: 1))
card(angle: 0, dx: 0, dy: 0, color: NSColor(red: 0.55, green: 0.80, blue: 0.85, alpha: 1))
card(angle: -16, dx: -110, dy: -20, color: NSColor(red: 0.97, green: 0.97, blue: 0.99, alpha: 1))
// 맨 앞 카드의 텍스트 줄
NSColor(red: 0.16, green: 0.20, blue: 0.36, alpha: 0.55).setFill()
for (i, w) in [220.0, 170.0, 200.0].enumerated() {
    let t = NSAffineTransform()
    t.translateX(by: size / 2 - 110, yBy: size / 2 - 20)
    t.rotate(byDegrees: -16)
    let p = NSBezierPath(roundedRect: NSRect(x: -w / 2, y: 100 - CGFloat(i) * 70, width: w, height: 26), xRadius: 13, yRadius: 13)
    p.transform(using: t as AffineTransform)
    p.fill()
}
NSGraphicsContext.restoreGraphicsState()

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let tmp = FileManager.default.temporaryDirectory.appending(path: "clipdeck-icon-\(getpid())")
let set = tmp.appending(path: "AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let master = tmp.appending(path: "master.png")
try rep.representation(using: .png, properties: [:])!.write(to: master)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        p.arguments = ["-z", "\(px)", "\(px)", master.path, "--out", set.appending(path: name).path]
        p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
    }
}
let out = root.appending(path: "Resources/AppIcon.icns")
let ic = Process()
ic.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
ic.arguments = ["-c", "icns", set.path, "-o", out.path]
try ic.run(); ic.waitUntilExit()
try? FileManager.default.removeItem(at: tmp)
print("생성: \(out.path)")
