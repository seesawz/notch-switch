import CoreGraphics
import XCTest

@testable import NotchKit

/// 缩略图的裁切与紧凑位图（v1.0.7 内存纪律）+ 内存读数口。
final class ThumbnailBitmapTests: XCTestCase {

    /// 造一张纯色图
    private func solidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// 读回输出图中心像素
    private func centerPixel(of image: CGImage) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = ((height / 2) * width + width / 2) * 4
        return (
            CGFloat(pixels[offset]) / 255,
            CGFloat(pixels[offset + 1]) / 255,
            CGFloat(pixels[offset + 2]) / 255
        )
    }

    private func assertColor(
        _ pixel: (r: CGFloat, g: CGFloat, b: CGFloat),
        red: CGFloat, green: CGFloat, blue: CGFloat,
        accuracy: CGFloat = 0.02,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(pixel.r, red, accuracy: accuracy, "红分量", file: file, line: line)
        XCTAssertEqual(pixel.g, green, accuracy: accuracy, "绿分量", file: file, line: line)
        XCTAssertEqual(pixel.b, blue, accuracy: accuracy, "蓝分量", file: file, line: line)
    }

    /// 竖长窗口（2:9）按 16:10 中心裁切：这正是旧实现最浪费的场景
    func testCropTallSourceToFixedCardSize() {
        let source = solidImage(width: 100, height: 450, red: 10, green: 200, blue: 30)
        let output = ThumbnailStore.cardCroppedBitmap(source, width: 352, height: 220)

        XCTAssertNotNil(output)
        XCTAssertEqual(output?.width, 352)
        XCTAssertEqual(output?.height, 220)
        assertColor(centerPixel(of: output!), red: 10.0 / 255, green: 200.0 / 255, blue: 30.0 / 255)
    }

    /// 横长窗口（32:9）裁左右保中心
    func testCropWideSourceToFixedCardSize() {
        let source = solidImage(width: 800, height: 225, red: 200, green: 10, blue: 30)
        let output = ThumbnailStore.cardCroppedBitmap(source, width: 352, height: 220)

        XCTAssertNotNil(output)
        XCTAssertEqual(output?.width, 352)
        XCTAssertEqual(output?.height, 220)
        assertColor(centerPixel(of: output!), red: 200.0 / 255, green: 10.0 / 255, blue: 30.0 / 255)
    }

    /// 恰好 16:10 的源：无裁切直通（ downsampling 1:1 ）
    func testExactAspectPassesThrough() {
        let source = solidImage(width: 352, height: 220, red: 128, green: 128, blue: 128)
        let output = ThumbnailStore.cardCroppedBitmap(source, width: 352, height: 220)

        XCTAssertNotNil(output)
        XCTAssertEqual(output?.width, 352)
        XCTAssertEqual(output?.height, 220)
        assertColor(centerPixel(of: output!), red: 128.0 / 255, green: 128.0 / 255, blue: 128.0 / 255)
    }

    /// 裁切保留的是**中心**内容（上下带状三色图，只有中段该出现）
    func testCropKeepsCenterBandOnly() {
        // 300×600（竖 1:2）：上 1/3 红、中 1/3 绿、下 1/3 蓝
        let context = CGContext(
            data: nil, width: 300, height: 600,
            bitsPerComponent: 8, bytesPerRow: 300 * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 400, width: 300, height: 200))   // 顶部（CG 坐标 y 向上）
        context.setFillColor(red: 0, green: 1, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 200, width: 300, height: 200))   // 中部
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))     // 底部
        let source = context.makeImage()!

        let output = ThumbnailStore.cardCroppedBitmap(source, width: 352, height: 220)!

        // 中心裁切高度 = 300/1.6 = 187.5，正好落在中部绿色带内
        assertColor(centerPixel(of: output), red: 0, green: 1, blue: 0)
    }

    /// 极端入参不崩、返回 nil（调用方回退存原图）
    func testDegenerateInputsReturnNil() {
        let tiny = solidImage(width: 1, height: 1, red: 0, green: 0, blue: 0)
        XCTAssertNil(ThumbnailStore.cardCroppedBitmap(tiny, width: 0, height: 220))
        XCTAssertNil(ThumbnailStore.cardCroppedBitmap(tiny, width: 352, height: 0))
    }

    /// 内存读数口：能读到正数，格式化非「未知」
    func testPhysicalFootprintReadable() {
        let bytes = MemoryInfo.physicalFootprintBytes()
        XCTAssertNotNil(bytes)
        XCTAssertGreaterThan(bytes!, 1_000_000, "一个跑着测试的进程不可能小于 1MB")
        XCTAssertTrue(MemoryInfo.physicalFootprintDescription().hasSuffix("MB"))
    }
}
