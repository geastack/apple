import UIKit
import XCTest

// Smoke test for the watchOS shell against the counter-jsx example: a tap must
// travel SwiftUI gesture -> gea touch dispatch -> reactive update -> repaint ->
// presented frame. The app is one image to XCUITest, so the checks compare
// screenshots below the system clock rather than query elements.
//
// counter-jsx is a centred column: + sits right of centre at ~64% height, and
// the top-left corner is empty background on every watch size.
final class GeaWatchCounterUITests: XCTestCase {
	private let app = XCUIApplication()

	override func setUp() {
		continueAfterFailure = false
		app.launch()
	}

	func testPlusTapRepaintsAndBackgroundTapDoesNot() throws {
		let initial = try settledScreen(named: "initial")

		tap(x: 0.04, y: 0.30)
		let afterBackgroundTap = try settledScreen(named: "after-background-tap")
		XCTAssertEqual(initial, afterBackgroundTap, "a tap on empty background changed the screen")

		tap(x: 0.69, y: 0.64)
		let afterPlus = try settledScreen(named: "after-plus")
		XCTAssertNotEqual(initial, afterPlus, "tapping + did not repaint the counter")

		tap(x: 0.69, y: 0.64)
		let afterSecondPlus = try settledScreen(named: "after-second-plus")
		XCTAssertNotEqual(afterPlus, afterSecondPlus, "a second tap on + did not repaint the counter")
	}

	private func tap(x: CGFloat, y: CGFloat) {
		app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
	}

	// Pixels of the screen below the clock, once two captures in a row agree.
	private func settledScreen(named name: String) throws -> Data {
		var previous = try appPixels()
		for _ in 0..<20 {
			Thread.sleep(forTimeInterval: 0.15)
			let current = try appPixels()
			if current == previous {
				let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
				attachment.name = name
				attachment.lifetime = .keepAlways
				add(attachment)
				return current
			}
			previous = current
		}
		XCTFail("screen never settled for \(name)")
		return previous
	}

	private func appPixels() throws -> Data {
		let png = XCUIScreen.main.screenshot().pngRepresentation
		let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
		let top = image.height / 4
		let region = try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: top, width: image.width, height: image.height - top)))
		let bytesPerRow = region.width * 4
		var pixels = Data(count: bytesPerRow * region.height)
		pixels.withUnsafeMutableBytes { buffer in
			guard let context = CGContext(data: buffer.baseAddress, width: region.width, height: region.height,
			                              bitsPerComponent: 8, bytesPerRow: bytesPerRow,
			                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
			                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
			context.draw(region, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
		}
		return pixels
	}
}
