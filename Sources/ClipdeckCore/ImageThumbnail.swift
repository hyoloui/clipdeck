import CoreGraphics
import Foundation
import ImageIO

/// 이미지 데이터를 긴 변 `maxPixel` 이하로 줄인다(작은 이미지는 키우지 않는다). 패널 미리보기와 MCP `get_item`이 같이 쓴다.
public enum ImageThumbnail {
    public static func make(data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary)
    }
}
