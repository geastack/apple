import XCTest

private struct ScrollTelemetry: CustomStringConvertible {
    let raw: String
    let values: [String: Double]

    init(_ value: Any?) {
        raw = value as? String ?? ""
        var parsed: [String: Double] = [:]
        for token in raw.split(separator: " ") {
            let pair = token.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, let number = Double(pair[1]) else { continue }
            parsed[String(pair[0])] = number
        }
        values = parsed
    }

    func number(_ key: String) -> Double {
        values[key] ?? .nan
    }

    var description: String {
        raw
    }
}

final class GeaIosRubberBandUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testNativeRubberBandReportsRawOverscrollExtrema() throws {
        let app = XCUIApplication()
        app.launchEnvironment["GEA_IOS_SCROLL_DEBUG_MARKERS"] = "1"
        app.launchArguments.append("--gea-scroll-debug-markers")
        app.launch()

        let scrollView = app.scrollViews["gea-native-scroll"].firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 8), "Expected the typography root to be backed by a native UIScrollView")

        XCTAssertTrue(waitUntil(timeout: 4) {
            let telemetry = ScrollTelemetry(scrollView.value)
            return telemetry.number("maxY") > 100
        }, "Expected scroll telemetry to publish a real maxY before gestures")

        let topDragStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        let topDragEnd = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        topDragStart.press(forDuration: 0.15, thenDragTo: topDragEnd)

        XCTAssertTrue(waitUntil(timeout: 2) {
            ScrollTelemetry(scrollView.value).number("minRawY") < -48
        }, "Expected a top-edge rubber-band drag to extend like native iOS rubber banding, not just dip a few pixels below zero. Last telemetry: \(ScrollTelemetry(scrollView.value))")

        let bottomDragStart = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        let bottomDragEnd = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18))
        for _ in 0..<8 {
            bottomDragStart.press(forDuration: 0.05, thenDragTo: bottomDragEnd)
        }
        bottomDragStart.press(forDuration: 0.15, thenDragTo: bottomDragEnd)

        XCTAssertTrue(waitUntil(timeout: 3) {
            let telemetry = ScrollTelemetry(scrollView.value)
            return telemetry.number("maxRawY") > telemetry.number("maxY") + 48
        }, "Expected a bottom-edge rubber-band drag to extend like native iOS rubber banding beyond maxY, not cut short. Last telemetry: \(ScrollTelemetry(scrollView.value))")

        let finalTelemetry = ScrollTelemetry(scrollView.value)
        let attachment = XCTAttachment(string: finalTelemetry.raw)
        attachment.name = "final-scroll-telemetry"
        attachment.lifetime = .keepAlways
        add(attachment)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "numeric-rubber-band-markers"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.05, predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(poll))
        } while Date() < deadline
        return predicate()
    }
}

final class GeaIosDeviceShowcaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOpenCameraPresentsNativeCameraSurface() throws {
        let app = XCUIApplication()
        app.launch()

        let cameraButton = app.buttons["Open camera"].firstMatch
        guard cameraButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("Current app does not expose the iOS device showcase camera button")
        }

        cameraButton.tap()

        let cameraPermission = app.alerts.firstMatch
        if cameraPermission.waitForExistence(timeout: 1) {
            let allow = cameraPermission.buttons["Allow"].firstMatch
            if allow.exists {
                allow.tap()
            } else if cameraPermission.buttons.count > 0 {
                cameraPermission.buttons.element(boundBy: cameraPermission.buttons.count - 1).tap()
            }
        }

        let closeButton = app.buttons["Close"].firstMatch
        let unavailableStatus = app.staticTexts["No camera device on this simulator"].firstMatch
        let runningStatus = app.staticTexts["READY"].firstMatch

        XCTAssertTrue(waitUntil(timeout: 5) {
            closeButton.exists || unavailableStatus.exists || runningStatus.exists
        }, "Expected tapping Open camera to present the native camera controller without terminating the app")

        if closeButton.exists || runningStatus.exists {
            XCTAssertTrue(app.staticTexts["ISO"].exists, "Expected a native camera metric tray")
            XCTAssertTrue(app.staticTexts["SHUTTER"].exists, "Expected shutter speed metric in the camera tray")
            XCTAssertTrue(app.staticTexts["EV"].exists, "Expected exposure compensation metric in the camera tray")
            XCTAssertTrue(app.staticTexts["FOCUS"].exists, "Expected focus metric in the camera tray")
            XCTAssertTrue(app.staticTexts["WB"].exists, "Expected white balance metric in the camera tray")
            XCTAssertTrue(app.buttons["Shutter"].exists, "Expected a prominent shutter control")
            XCTAssertTrue(app.staticTexts["PHOTO"].exists, "Expected a camera mode strip")
            XCTAssertTrue(app.staticTexts["PRO"].exists, "Expected Pro mode in the camera mode strip")
        }

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "ios-device-showcase-camera"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        if closeButton.exists {
            closeButton.tap()
            XCTAssertTrue(
                cameraButton.waitForExistence(timeout: 3),
                "Expected the camera close button to dismiss back to the device showcase"
            )
        }
    }

    func testCameraSurfaceControlsPublishFeedback() throws {
        let app = XCUIApplication()
        app.launch()

        let cameraButton = app.buttons["Open camera"].firstMatch
        guard cameraButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("Current app does not expose the iOS device showcase camera button")
        }

        cameraButton.tap()
        dismissSystemPermissionAlertIfNeeded(app)

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5), "Expected camera surface to open")

        tap(app.buttons["Flash"].firstMatch)
        XCTAssertTrue(app.staticTexts["FLASH AUTO"].waitForExistence(timeout: 2), "Expected flash control to cycle and report feedback")
        tap(app.buttons["Flash"].firstMatch)
        XCTAssertTrue(app.staticTexts["FLASH ON"].waitForExistence(timeout: 2), "Expected flash state to persist across repeated taps")
        tap(app.buttons["Flash"].firstMatch)
        XCTAssertTrue(app.staticTexts["FLASH OFF"].waitForExistence(timeout: 2), "Expected flash state to cycle back to off")

        tap(app.buttons["Grid"].firstMatch)
        XCTAssertTrue(app.staticTexts["GRID OFF"].waitForExistence(timeout: 2), "Expected grid control to toggle composition grid")
        tap(app.buttons["Grid"].firstMatch)
        XCTAssertTrue(app.staticTexts["GRID ON"].waitForExistence(timeout: 2), "Expected grid control to restore the composition grid")

        tap(app.buttons["Camera Options"].firstMatch)
        XCTAssertTrue(app.staticTexts["TOOLS HIDDEN"].waitForExistence(timeout: 2), "Expected options control to collapse the camera tray")

        tap(app.buttons["Camera Options"].firstMatch)
        XCTAssertTrue(app.staticTexts["TOOLS VISIBLE"].waitForExistence(timeout: 2), "Expected options control to restore the camera tray")

        tap(app.buttons["Photo resolution"].firstMatch)
        XCTAssertTrue(
            app.staticTexts["HIGH RES"].waitForExistence(timeout: 2) ||
            app.staticTexts["Camera configuration lock unavailable"].waitForExistence(timeout: 2),
            "Expected resolution control to attempt a native session preset change"
        )

        tap(app.buttons["Photo quality"].firstMatch)
        XCTAssertTrue(app.staticTexts["QUALITY BALANCED"].waitForExistence(timeout: 2), "Expected quality control to cycle capture quality")

        tap(app.buttons["ISO"].firstMatch)
        XCTAssertTrue(
            app.staticTexts["MANUAL EXPOSURE"].waitForExistence(timeout: 2) ||
            app.staticTexts["EXPOSURE AUTO"].waitForExistence(timeout: 2) ||
            app.staticTexts["ISO 200"].waitForExistence(timeout: 2),
            "Expected ISO control to update exposure state"
        )
        tap(app.buttons["SHUTTER"].firstMatch)
        XCTAssertTrue(
            app.staticTexts["MANUAL EXPOSURE"].waitForExistence(timeout: 2) ||
            app.staticTexts["EXPOSURE AUTO"].waitForExistence(timeout: 2) ||
            app.staticTexts["SHUTTER 1/125"].waitForExistence(timeout: 2),
            "Expected shutter metric to update exposure state"
        )
        tap(app.buttons["EV"].firstMatch)
        XCTAssertTrue(
            app.staticTexts["EV +1.0"].waitForExistence(timeout: 2) ||
            app.staticTexts["EV -1.0"].waitForExistence(timeout: 2) ||
            app.staticTexts["EV +1"].waitForExistence(timeout: 2) ||
            app.staticTexts["EV -1"].waitForExistence(timeout: 2) ||
            app.staticTexts["EV 0.0"].waitForExistence(timeout: 2) ||
            app.staticTexts["Camera configuration lock unavailable"].waitForExistence(timeout: 2),
            "Expected EV control to update exposure bias"
        )
        tap(app.buttons["FOCUS"].firstMatch)
        XCTAssertTrue(app.staticTexts["FOCUS LOCKED"].waitForExistence(timeout: 2), "Expected focus metric to lock native focus")
        tap(app.buttons["WB"].firstMatch)
        XCTAssertTrue(app.staticTexts["WB LOCKED"].waitForExistence(timeout: 2) || app.staticTexts["Camera configuration lock unavailable"].waitForExistence(timeout: 2), "Expected white balance control to update native mode")

        tap(app.buttons["PHOTO"].firstMatch)
        XCTAssertTrue(app.staticTexts["PHOTO MODE"].waitForExistence(timeout: 2), "Expected Photo mode control to publish feedback")
        tap(app.buttons["PORTRAIT"].firstMatch)
        XCTAssertTrue(app.staticTexts["PORTRAIT MODE"].waitForExistence(timeout: 2), "Expected Portrait mode control to publish feedback")
        tap(app.buttons["STREET"].firstMatch)
        XCTAssertTrue(app.staticTexts["STREET MODE"].waitForExistence(timeout: 2), "Expected Street mode control to publish feedback")
        tap(app.buttons["VIDEO"].firstMatch)
        XCTAssertTrue(app.staticTexts["VIDEO MODE"].waitForExistence(timeout: 2), "Expected Video mode control to publish feedback")
        tap(app.buttons["PRO"].firstMatch)
        XCTAssertTrue(app.staticTexts["PRO MODE"].waitForExistence(timeout: 2), "Expected Pro mode control to publish feedback")

        tapFirstExistingButton(app, labels: ["1x", "2x", "4x", "8x"])
        XCTAssertTrue(
            app.staticTexts["LENS 1x"].waitForExistence(timeout: 2) ||
            app.staticTexts["LENS 2x"].waitForExistence(timeout: 2) ||
            app.staticTexts["LENS 4x"].waitForExistence(timeout: 2) ||
            app.staticTexts["LENS 8x"].waitForExistence(timeout: 2),
            "Expected lens controls to expose and switch away from the ultrawide stop"
        )

        tap(app.buttons["AE/AF Center"].firstMatch)
        XCTAssertTrue(app.staticTexts["AE/AF LOCKED"].waitForExistence(timeout: 2), "Expected focus control to publish focus feedback")

        tap(app.buttons["Photos"].firstMatch)
        let photosApp = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow")
        let didOpenPhotos = photosApp.wait(for: .runningForeground, timeout: 4)
        let didReportOpen = didOpenPhotos ? false : app.staticTexts["PHOTOS OPENED"].waitForExistence(timeout: 2)
        XCTAssertTrue(
            didOpenPhotos || didReportOpen,
            "Expected Photos control to open the system Photos app or report successful URL handoff"
        )
        if didOpenPhotos {
            app.activate()
            XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3), "Expected returning from Photos to restore the camera surface")
        }

        tap(app.buttons["Shutter"].firstMatch)
        dismissSystemPermissionAlertIfNeeded(app)
        XCTAssertTrue(
            app.staticTexts["NO CAMERA"].waitForExistence(timeout: 2) ||
            app.staticTexts["CAPTURING"].waitForExistence(timeout: 2) ||
            app.staticTexts["SAVING"].waitForExistence(timeout: 2) ||
            app.staticTexts["SAVED TO PHOTOS"].waitForExistence(timeout: 2) ||
            app.staticTexts["CAPTURE FAILED"].waitForExistence(timeout: 2) ||
            app.staticTexts["PHOTOS SAVE FAILED"].waitForExistence(timeout: 2),
            "Expected shutter to trigger capture feedback"
        )

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "ios-device-showcase-camera-controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        tap(app.buttons["Close"].firstMatch)
        XCTAssertTrue(
            cameraButton.waitForExistence(timeout: 3),
            "Expected Close to dismiss after exercising the camera controls"
        )
    }

    private func waitUntil(timeout: TimeInterval, poll: TimeInterval = 0.05, predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(poll))
        } while Date() < deadline
        return predicate()
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), "Expected tappable control \(element)")
        XCTAssertTrue(element.isHittable, "Expected control to be hittable: \(element)")
        element.tap()
    }

    private func tapFirstExistingButton(_ app: XCUIApplication, labels: [String]) {
        for label in labels {
            let button = app.buttons[label].firstMatch
            if button.waitForExistence(timeout: 0.5) {
                tap(button)
                return
            }
        }
        XCTFail("Expected one of these buttons to exist: \(labels.joined(separator: ", "))")
    }

    private func dismissSystemPermissionAlertIfNeeded(_ app: XCUIApplication) {
        let permission = app.alerts.firstMatch
        if permission.waitForExistence(timeout: 1) {
            let allow = permission.buttons["Allow"].firstMatch
            if allow.exists {
                allow.tap()
            } else if permission.buttons.count > 0 {
                permission.buttons.element(boundBy: permission.buttons.count - 1).tap()
            }
        }
    }
}

final class GeaIosMetalWorldDriveUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFireButtonPublishesControlStateWithoutNaN() throws {
        let app = XCUIApplication()
        app.launch()

        let fireButton = app.buttons["Fire"].firstMatch
        guard fireButton.waitForExistence(timeout: 8) else {
            throw XCTSkip("Current app does not expose the Metal world arcade controls")
        }

        fireButton.tap()

        let scoreLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Score "))
            .firstMatch
        XCTAssertTrue(
            scoreLabel.waitForExistence(timeout: 3),
            "Expected tapping Fire to keep the Metal world HUD alive through UIKit control callbacks.\n\(app.debugDescription)"
        )
        XCTAssertFalse(app.staticTexts["Score NaN"].exists, "Score should stay numeric after control input")
        XCTAssertFalse(app.staticTexts["Shield NaN%"].exists, "Shield should stay numeric after control input")

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "ios-metal-world-arcade-fire-control"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
