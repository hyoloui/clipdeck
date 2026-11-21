import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ClipdeckCore

private func makePNG(width: Int, height: Int) throws -> Data {
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let out = NSMutableData()
    let dest = try #require(CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
    #expect(CGImageDestinationFinalize(dest))
    return out as Data
}

@Suite struct ImageThumbnailTests {
    @Test func scalesLongSideTo800() throws {
        let image = try #require(ImageThumbnail.make(data: try makePNG(width: 2048, height: 1024), maxPixel: 800))
        #expect(image.width == 800)
        #expect(image.height == 400)
    }

    @Test func smallImageNotEnlarged() throws {
        let image = try #require(ImageThumbnail.make(data: try makePNG(width: 300, height: 200), maxPixel: 800))
        #expect(image.width == 300 && image.height == 200)
    }

    @Test func garbageIsNil() {
        #expect(ImageThumbnail.make(data: Data("not an image".utf8), maxPixel: 800) == nil)
    }
}
