import CoreGraphics

/// 간격·크기 상수. 모두 4pt 배수만 쓴다.
enum Layout {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24

    static let panelWidth: CGFloat = 760
    static let panelHeight: CGFloat = 480
    static let listWidth: CGFloat = 420
    static let rowHeight: CGFloat = 32
    static let rowCorner: CGFloat = 8
    static let numberWidth: CGFloat = 16
    static let iconWidth: CGFloat = 16
    static let appColumnWidth: CGFloat = 96
    static let timeColumnWidth: CGFloat = 64
    static let swatchSize: CGFloat = 64
}
