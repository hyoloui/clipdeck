import CoreGraphics

/// 패널을 띄울 위치 계산(화면 좌표, 좌하단 원점)
public enum PanelPlacement {
    /// 저장된 위치가 없으면 화면 중앙(정수 좌표). 있으면 패널 전체가 보이도록 안쪽으로 당긴다.
    /// 패널이 화면보다 크면 당겨도 다 보일 수 없으므로 중앙.
    public static func origin(saved: CGPoint?, panelSize: CGSize, visibleFrame f: CGRect) -> CGPoint {
        let centered = CGPoint(x: (f.midX - panelSize.width / 2).rounded(),
                               y: (f.midY - panelSize.height / 2).rounded())
        guard let saved, panelSize.width <= f.width, panelSize.height <= f.height else { return centered }
        return CGPoint(x: min(max(saved.x, f.minX), f.maxX - panelSize.width),
                       y: min(max(saved.y, f.minY), f.maxY - panelSize.height))
    }
}
