// ShadyGarageSpeedUITests.swift — end-to-end UI tests driving the real app.
// Asserts are SwiftUI-HUD only (SceneKit content isn't visible to XCUITest).
// Orientation is managed deterministically: portrait forced before every launch,
// landscape tests rotate the device BEFORE launching the app. NOTE: this XCTest
// build synthesizes taps in a stale (portrait) coordinate space after a mid-session
// rotation, so the landscape test uses deep-link launch args instead of taps.
import XCTest

final class ShadyGarageSpeedUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app = nil
    }

    @discardableResult
    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        self.app = app
        return app
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval) -> Bool {
        let pred = NSPredicate(format: "label CONTAINS %@", text)
        let exp = XCTNSPredicateExpectation(predicate: pred, object: element)
        return XCTWaiter.wait(for: [exp], timeout: timeout) == .completed
    }

    private func digits(_ s: String) -> Int? {
        Int(s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined())
    }

    private func tapFirstEnabled(_ prefix: String, range: ClosedRange<Int>) -> Bool {
        for i in range {
            let b = app.buttons["\(prefix)-\(i)"]
            if b.exists && b.isEnabled {
                b.tap()
                return true
            }
        }
        return false
    }

    /// menu → setup → garage: fix a worn part, steal a part via the minigame, finish the job.
    func testGarageLoop() throws {
        launch(["-reset", "-phase", "setup"])
        XCTAssertTrue(app.buttons["start-day1"].waitForExistence(timeout: 5))
        app.buttons["friend-card-2"].tap() // Dex: +$25 per fix
        app.buttons["start-day1"].tap()

        // wait for the customer to finish parking (inspect phase begins)
        let prompt = app.staticTexts["garage-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(prompt, contains: "Tap a part", timeout: 15))

        // fix the first worn part → job total > $0
        XCTAssertTrue(tapFirstEnabled("fix", range: 0...5), "no fixable part")
        let total = app.staticTexts["job-total"].label
        XCTAssertTrue((digits(total) ?? 0) > 0, "job total should be > 0, got \(total)")
        shot("garage_after_fix")

        // steal any available part → timing minigame modal → lock it
        XCTAssertTrue(tapFirstEnabled("steal", range: 0...5), "no stealable part")
        let swap = app.buttons["mg-swap"]
        XCTAssertTrue(swap.waitForExistence(timeout: 3))
        shot("garage_minigame")
        swap.tap()
        XCTAssertTrue(swap.waitForNonExistence(timeout: 5))

        // finish the job → next day, cash increased
        let finish = app.buttons["finish-job"]
        XCTAssertTrue(finish.isEnabled)
        finish.tap()
        XCTAssertTrue(waitLabel(app.staticTexts["hud-day"], contains: "Day 2", timeout: 5))
        let cash = digits(app.staticTexts["hud-cash"].label) ?? 0
        XCTAssertGreaterThan(cash, 200, "cash should increase after a paid job")
        shot("garage_after_finish")
    }

    /// build bay: stats render, installing the seeded tier-3 engine raises Speed.
    func testBuildBay() throws {
        launch(["-reset", "-seedparts", "-phase", "garage"])
        let build = app.buttons["nav-build"]
        XCTAssertTrue(build.waitForExistence(timeout: 8))
        build.tap()
        let speed = app.staticTexts["stat-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        XCTAssertEqual(speed.label, "27") // L1 chassis base
        shot("build_before_install")
        app.buttons["install-0"].tap() // seeded engine, tier 3 (+11 speed/tier)
        XCTAssertEqual(speed.label, "60")
        shot("build_after_install")
    }

    /// race: hold GAS, speed climbs, forfeit ✕ returns to the garage.
    func testRace() throws {
        launch(["-reset", "-phase", "garage"])
        let race = app.buttons["nav-race"]
        XCTAssertTrue(race.waitForExistence(timeout: 8))
        race.tap()
        sleep(4) // 3s countdown + GO (~1s into the race now)
        let gas = app.buttons["tc-gas"]
        XCTAssertTrue(gas.waitForExistence(timeout: 3))
        gas.press(forDuration: 2) // short enough to read the speedo before any barrier crash
        let kmh = digits(app.staticTexts["race-speed"].label) ?? 0
        XCTAssertGreaterThan(kmh, 0, "speed should climb while GAS held")
        shot("race_hud")
        app.buttons["forfeit"].tap()
        XCTAssertTrue(app.buttons["nav-build"].waitForExistence(timeout: 5))
    }

    /// build bay catalog: buying a Sport engine ($160) from the Catalog tab takes
    /// the cash ($200 → $40) and drops the part into the inventory.
    func testCatalogBuy() throws {
        launch(["-reset", "-phase", "build"])
        let catalog = app.buttons["tab-catalog"]
        XCTAssertTrue(catalog.waitForExistence(timeout: 8))
        catalog.tap()
        let buy = app.buttons["catalog-buy-engine-2"] // Sport engine, $160
        XCTAssertTrue(buy.waitForExistence(timeout: 3))
        XCTAssertTrue(buy.isEnabled, "catalog buy should be affordable with the $200 start")
        buy.tap()
        XCTAssertTrue(waitLabel(app.staticTexts["build-cash"], contains: "$40", timeout: 3),
                      "cash should drop to $40, got \(app.staticTexts["build-cash"].label)")
        app.buttons["tab-inventory"].tap()
        XCTAssertTrue(app.buttons["install-0"].waitForExistence(timeout: 3),
                      "bought part should appear in the inventory")
        shot("build_catalog")
    }

    /// suspicion is per-customer: it must NOT survive an app relaunch onto a fresh
    /// customer. Steal (any zone raises the meter), kill the app, relaunch → 0.
    func testSuspicionResetsAfterRelaunch() throws {
        launch(["-reset", "-phase", "garage"])
        let prompt = app.staticTexts["garage-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(prompt, contains: "Tap a part", timeout: 15))
        XCTAssertTrue(tapFirstEnabled("steal", range: 0...5), "no stealable part")
        let swap = app.buttons["mg-swap"]
        XCTAssertTrue(swap.waitForExistence(timeout: 3))
        swap.tap()
        XCTAssertTrue(swap.waitForNonExistence(timeout: 5))
        let susp = app.staticTexts["hud-suspicion"]
        XCTAssertTrue(susp.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(digits(susp.label) ?? 0, 0, "steal should raise suspicion")
        app.terminate()

        launch(["-phase", "garage"]) // NO -reset: the save reloads
        XCTAssertTrue(app.staticTexts["hud-suspicion"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["hud-suspicion"].label, "0",
                       "suspicion must reset to 0 after a relaunch")
        shot("relaunch_suspicion_zero")
    }

    /// landscape: garage HUD + race controls must fit sideways. Runs LAST (name sorts
    /// after the other tests) so its device rotation can't leak into them — this XCTest
    /// build mis-synthesizes tap/isHittable coordinates for the rest of a session once
    /// the device has been rotated (nav-race taps landed at stale portrait points).
    /// Assertions here are existence-based (queries stay correct); hittability in
    /// landscape is verified via the screenshots.
    func testZZZLandscape() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2) // let the rotation fully apply before launching

        // garage HUD in landscape
        launch(["-reset", "-phase", "garage"])
        XCTAssertTrue(app.buttons["finish-job"].waitForExistence(timeout: 15))
        shot("landscape_garage")
        XCTAssertTrue(app.buttons["nav-build"].exists, "Build missing in landscape")
        XCTAssertTrue(app.buttons["nav-race"].exists, "Race missing in landscape")
        XCTAssertTrue(app.buttons["finish-job"].exists, "job panel missing in landscape")

        // race HUD in landscape (deep link into a fresh instance)
        app.terminate()
        sleep(1)
        launch(["-reset", "-phase", "race", "-rain", "off"])
        sleep(4) // countdown + GO
        shot("landscape_race")
        XCTAssertTrue(app.buttons["tc-gas"].waitForExistence(timeout: 5), "GAS missing in landscape")
        XCTAssertTrue(app.buttons["tc-left"].exists, "steer-left missing in landscape")
        XCTAssertTrue(app.buttons["tc-brake"].exists, "BRK missing in landscape")
        XCTAssertTrue(app.buttons["tc-nos"].exists, "NOS missing in landscape")
        XCTAssertTrue(app.buttons["forfeit"].exists, "forfeit missing in landscape")
        XCTAssertTrue(app.staticTexts["race-timer"].exists, "timer missing in landscape")
    }
}
