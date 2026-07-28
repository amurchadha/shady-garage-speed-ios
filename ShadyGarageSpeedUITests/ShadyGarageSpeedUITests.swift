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

    /// contracts board: a seeded Pro Engine order plus seeded tier-3 parts →
    /// Fulfill consumes the lowest matching part and pays 60·3·2.2 = $396.
    func testContractFulfill() throws {
        launch(["-reset", "-seedparts", "-contract", "engine", "3", "-phase", "build"])
        let fulfill = app.buttons["contract-fulfill"]
        XCTAssertTrue(fulfill.waitForExistence(timeout: 8))
        XCTAssertTrue(fulfill.isEnabled)
        fulfill.tap()
        XCTAssertTrue(waitLabel(app.staticTexts["build-cash"], contains: "$596", timeout: 3),
                      "cash should be 200 + 396, got \(app.staticTexts["build-cash"].label)")
        XCTAssertFalse(app.buttons["contract-fulfill"].exists, "contract should be consumed")
        // 8 seeded t3 parts (#8/#9 added nitrous + ecu); fulfilling drops one → install-7 gone
        XCTAssertFalse(app.buttons["install-7"].exists, "one of the 8 seeded parts should be consumed")
        XCTAssertTrue(app.buttons["install-0"].exists)
        shot("contract_fulfilled")
    }

    /// crew hire: debug cash → hire Dex ($2000) → join toast confirms the perk,
    /// the Hire button becomes HIRED ✓, cash drops to $1000.
    func testCrewHire() throws {
        launch(["-reset", "-cash", "3000", "-phase", "garage"])
        let crew = app.buttons["nav-crew"]
        XCTAssertTrue(crew.waitForExistence(timeout: 8))
        crew.tap()
        let hire = app.buttons["hire-2"] // Dex — $2000
        XCTAssertTrue(hire.waitForExistence(timeout: 5))
        XCTAssertTrue(hire.isEnabled)
        hire.tap()
        XCTAssertTrue(app.staticTexts["Dex joined the crew! +$25 per Fix"].waitForExistence(timeout: 3),
                      "perk toast should confirm the hire")
        XCTAssertFalse(hire.exists, "Hire button should become HIRED ✓")
        XCTAssertTrue(waitLabel(app.staticTexts["hud-cash"], contains: "$1,000", timeout: 3),
                      "cash should count down to 1000, got \(app.staticTexts["hud-cash"].label)")
        shot("crew_hired")
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

    /// VoiceOver audit: key controls expose human-readable labels (not test ids),
    /// and `-vo-sim` swaps the timing minigame for explicit risk-choice buttons.
    func testAccessibility() throws {
        launch(["-reset", "-phase", "garage"])
        let prompt = app.staticTexts["garage-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(prompt, contains: "Tap a part", timeout: 15))

        // human-readable labels, not identifiers
        XCTAssertEqual(app.buttons["nav-build"].label, "Build bay")
        XCTAssertEqual(app.buttons["nav-race"].label, "Race")
        XCTAssertEqual(app.buttons["nav-ladder"].label, "Rival ladder")
        XCTAssertEqual(app.buttons["nav-crew"].label, "Hire crew")
        XCTAssertFalse(app.buttons["finish-job"].label.isEmpty)
        XCTAssertTrue(app.buttons["fix-0"].label.contains("Fix"))
        XCTAssertTrue(app.buttons["steal-0"].label.contains("Steal"))
        XCTAssertTrue(app.buttons["steal-0"].label.contains("tier"),
                      "steal label should name the part tier, got \(app.buttons["steal-0"].label)")

        // race touch controls are labeled buttons
        app.buttons["nav-race"].tap()
        XCTAssertTrue(app.buttons["track-row-0"].waitForExistence(timeout: 5))
        app.buttons["track-row-0"].tap()
        XCTAssertTrue(app.buttons["tc-gas"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["tc-gas"].label, "Gas")
        XCTAssertEqual(app.buttons["tc-nos"].label, "NOS boost")
        XCTAssertEqual(app.buttons["tc-brake"].label, "Brake")
        app.buttons["forfeit"].tap()
        XCTAssertTrue(app.buttons["nav-build"].waitForExistence(timeout: 5))

        // -vo-sim: accessible minigame replaces the timing bar
        launch(["-reset", "-vo-sim", "-phase", "garage"])
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(prompt, contains: "Tap a part", timeout: 15))
        XCTAssertTrue(tapFirstEnabled("steal", range: 0...5), "no stealable part")
        XCTAssertFalse(app.buttons["mg-swap"].exists, "timing bar must be hidden in accessible mode")
        let careful = app.buttons["mg-careful"]
        XCTAssertTrue(careful.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["mg-quick"].exists)
        XCTAssertTrue(app.buttons["mg-force"].exists)
        shot("accessible_minigame_modal")
        app.buttons["mg-quick"].tap() // deterministic yellow outcome
        XCTAssertTrue(careful.waitForNonExistence(timeout: 5))
        let susp = app.staticTexts["hud-suspicion"]
        XCTAssertTrue(susp.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(digits(susp.label) ?? 0, 0, "quick grab should raise suspicion")
        shot("accessibility_minigame")
    }

    /// customer archetypes: a Skeptic multiplies suspicion gains ×1.5 (red zone
    /// 35 → 52.5 → 53). -mgzone red makes the steal outcome deterministic and
    /// -nowatch keeps the owner's watch cycle from adding its own ×1.5.
    func testArchetypeSkepticSuspicion() throws {
        launch(["-reset", "-arch", "skeptic", "-mgzone", "red", "-nowatch", "-phase", "garage"])
        let prompt = app.staticTexts["garage-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(prompt, contains: "Tap a part", timeout: 15))
        let badge = app.staticTexts["arch-badge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 3))
        XCTAssertEqual(badge.label, "🧐")
        XCTAssertTrue(tapFirstEnabled("steal", range: 0...5), "no stealable part")
        let swap = app.buttons["mg-swap"]
        XCTAssertTrue(swap.waitForExistence(timeout: 3))
        swap.tap()
        XCTAssertTrue(swap.waitForNonExistence(timeout: 5))
        let susp = app.staticTexts["hud-suspicion"]
        XCTAssertTrue(susp.waitForExistence(timeout: 3))
        XCTAssertEqual(susp.label, "53", "skeptic red-zone steal should be 35 × 1.5 = 53")
        shot("archetype_skeptic")
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
        // #68 tier/type sort among the eight seeded t3 parts: body kit 0, ecu 1, ENGINE 2
        app.buttons["install-2"].tap() // seeded engine, tier 3 (+11 speed/tier)
        XCTAssertEqual(speed.label, "60")
        shot("build_after_install")
    }

    /// pink-slip ladder: challenge Granny Shift with a fixed rival time (-ladderwin)
    /// and an auto-finished lap (-instantfinish) → the win advances the ladder and
    /// drops the Sport Tires prize into the inventory.
    func testLadderChallengeWin() throws {
        launch(["-reset", "-ladderwin", "-instantfinish", "-phase", "garage"])
        let ladder = app.buttons["nav-ladder"]
        XCTAssertTrue(ladder.waitForExistence(timeout: 8))
        ladder.tap()
        let challenge = app.buttons["ladder-challenge"]
        XCTAssertTrue(challenge.waitForExistence(timeout: 5))
        challenge.tap() // dismisses the sheet and deep-links into the pink-slip race

        XCTAssertTrue(app.staticTexts["pinkslip-banner"].waitForExistence(timeout: 8))
        let header = app.staticTexts["results-pinkslip"]
        XCTAssertTrue(header.waitForExistence(timeout: 25), "no pink-slip results")
        XCTAssertEqual(header.label, "🏆 PINK SLIP WIN!")
        shot("pinkslip_results")

        app.buttons["results-back"].tap()
        XCTAssertTrue(ladder.waitForExistence(timeout: 5))
        ladder.tap()
        XCTAssertTrue(app.buttons["ladder-close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["ladder-row-0"].label, "✓", "Granny row should be beaten")
        XCTAssertEqual(app.staticTexts["ladder-row-1"].label, "🏁", "Lugnut should be the next rival")
        app.buttons["ladder-close"].tap()
        sleep(1) // let the sheet finish dismissing

        app.buttons["nav-build"].tap()
        XCTAssertTrue(app.buttons["install-0"].waitForExistence(timeout: 5),
                      "prize part should be in the inventory")
    }

    /// ghost-car regression: at heat ≥70 the cop path interrupts customer entry, and
    /// the old double enterPlay (AppState + view onAppear) could spawn a duplicate
    /// customer car. Entry is now single-sourced (AppState) and idempotent.
    /// -cop makes the visit deterministic, -debughud exposes the live car count.
    func testHeat75RelaunchSingleCustomerCar() throws {
        launch(["-reset", "-heat", "75", "-cop", "-debughud", "-phase", "garage"])
        XCTAssertTrue(app.buttons["cop-laylow"].waitForExistence(timeout: 10),
                      "cop modal should appear at heat 75")
        app.terminate()

        launch(["-heat", "75", "-cop", "-debughud", "-phase", "garage"]) // NO -reset
        let bribe = app.buttons["cop-bribe"]
        XCTAssertTrue(bribe.waitForExistence(timeout: 10), "cop modal should reappear after relaunch")
        bribe.tap() // pay → exactly one customer spawns
        let cars = app.staticTexts["debug-cars"]
        XCTAssertTrue(cars.waitForExistence(timeout: 5))
        XCTAssertTrue(waitLabel(cars, contains: "1", timeout: 10),
                      "customer car should spawn, got \(cars.label)")
        sleep(4) // past the full arrival tween — still exactly one car
        XCTAssertEqual(cars.label, "cars:1", "no duplicate/ghost customer car in-scene")
        shot("heat75_single_car")
    }

    /// race: track sheet first, then hold GAS, speed climbs, forfeit ✕ returns to the garage.
    func testRace() throws {
        launch(["-reset", "-phase", "garage"])
        let race = app.buttons["nav-race"]
        XCTAssertTrue(race.waitForExistence(timeout: 8))
        race.tap()
        XCTAssertTrue(app.buttons["track-row-0"].waitForExistence(timeout: 5),
                      "Race must open the track-select sheet first")
        app.buttons["track-row-0"].tap()
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

    /// backgrounding mid-race: the sim freezes (timer can't jump), held inputs are
    /// dropped, and audio loops stop. NOTE: the exact touch-cancel latch can't be
    /// synthesized deterministically (XCUITest presses block the test thread), so
    /// this asserts the observable contract: HUD intact after resume, speed must
    /// not climb with no finger down, timer delta stays sane.
    func testRaceBackgroundPause() throws {
        launch(["-reset", "-phase", "race", "-rain", "off"])
        let gas = app.buttons["tc-gas"]
        XCTAssertTrue(gas.waitForExistence(timeout: 8))
        sleep(4) // countdown + GO
        gas.press(forDuration: 2)
        let speedBefore = digits(app.staticTexts["race-speed"].label) ?? 0
        let timerBefore = digits(app.staticTexts["race-timer"].label) ?? 0
        XCTAssertGreaterThan(speedBefore, 0)

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["race-speed"].waitForExistence(timeout: 5))
        sleep(2) // a latched GAS would keep accelerating through this window

        let speedAfter = digits(app.staticTexts["race-speed"].label) ?? 0
        XCTAssertLessThanOrEqual(speedAfter, speedBefore,
                                 "speed must not climb after background/foreground (\(speedBefore) → \(speedAfter))")
        let timerAfter = digits(app.staticTexts["race-timer"].label) ?? 0
        XCTAssertLessThan(timerAfter - timerBefore, 5000,
                          "timer jumped unreasonably (\(timerBefore) → \(timerAfter))")
        shot("race_after_background")
    }

    /// track select: Race opens the sheet; picking Figure-8 Ridge starts a race there.
    func testTrackSelectFlow() throws {
        launch(["-reset", "-phase", "garage"])
        let race = app.buttons["nav-race"]
        XCTAssertTrue(race.waitForExistence(timeout: 8))
        race.tap()
        let ridge = app.buttons["track-row-1"]
        XCTAssertTrue(ridge.waitForExistence(timeout: 5), "track sheet should offer Figure-8 Ridge")
        XCTAssertTrue(app.buttons["track-row-0"].exists, "track sheet should offer Meadow Loop")
        ridge.tap()
        XCTAssertTrue(app.staticTexts["race-timer"].waitForExistence(timeout: 8),
                      "race should start on the Ridge")
        shot("track_ridge")
        app.buttons["forfeit"].tap()
        XCTAssertTrue(app.buttons["nav-race"].waitForExistence(timeout: 5))
    }

    /// difficulty: set Cutthroat in Settings, relaunch — the menu footer shows it.
    /// (Restores Normal afterwards so the rest of the suite runs stock.)
    func testDifficultyPersist() throws {
        launch(["-reset", "-phase", "garage"])
        let gear = app.buttons["nav-settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 8))
        gear.tap()
        let cut = app.buttons["set-diff-cutthroat"]
        XCTAssertTrue(cut.waitForExistence(timeout: 5))
        cut.tap()
        app.buttons["settings-close"].tap()
        app.terminate()

        launch([]) // menu, NO -reset — settings persist outside the save blob
        let footer = app.staticTexts["menu-footer"]
        XCTAssertTrue(footer.waitForExistence(timeout: 8))
        XCTAssertTrue(footer.label.contains("Cutthroat"),
                      "difficulty should persist across relaunch, got \(footer.label)")

        // leave no trace for the rest of the suite
        launch(["-phase", "garage"])
        XCTAssertTrue(app.buttons["nav-settings"].waitForExistence(timeout: 8))
        app.buttons["nav-settings"].tap()
        XCTAssertTrue(app.buttons["set-diff-normal"].waitForExistence(timeout: 5))
        app.buttons["set-diff-normal"].tap()
    }

    /// first-run tutorial: 3 coach marks appear on the first garage visit,
    /// advance with Next, and never come back after being seen.
    func testTutorialAppearsOnce() throws {
        launch(["-reset", "-phase", "garage"])
        let next = app.buttons["tutorial-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10), "tutorial should show on first visit")
        shot("tutorial_first")
        next.tap() // mark 2
        next.tap() // mark 3
        next.tap() // Got it
        XCTAssertTrue(next.waitForNonExistence(timeout: 5), "tutorial should dismiss")
        app.terminate()

        launch(["-phase", "garage"]) // NO -reset
        sleep(2)
        XCTAssertFalse(app.buttons["tutorial-next"].exists,
                       "tutorial must not reappear after being seen")
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

    /// #15 clean-job streak: seeded at 2, one clean job → streak 3 pays +25%
    /// with the "Clean streak x3 — bonus!" toast and the 🔥 chip in the topbar.
    func testCleanStreakBonus() throws {
        launch(["-reset", "-phase", "garage", "-notut", "-streak", "2"])
        let prompt = app.staticTexts["garage-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(prompt, contains: "Tap a part", timeout: 15))

        XCTAssertTrue(tapFirstEnabled("fix", range: 0...5), "no fixable part")
        let finish = app.buttons["finish-job"]
        XCTAssertTrue(finish.isEnabled)
        finish.tap()

        XCTAssertTrue(app.staticTexts["Clean streak x3 — bonus!"].waitForExistence(timeout: 5),
                      "streak toast should fire on the 3rd clean job")
        let chip = app.staticTexts["streak-chip"]
        XCTAssertTrue(chip.waitForExistence(timeout: 3), "🔥 chip should show at streak ≥2")
        XCTAssertTrue(waitLabel(chip, contains: "3", timeout: 2),
                      "chip should read 3, got \(chip.label)")
        shot("streak_bonus")
    }

    /// #67 bulk sell + #66 Pro confirm: seeded 6 Pro parts + 3 Stock → Sell Stock
    /// clears the stock in one toast; selling a Pro opens the priced confirm alert.
    func testSellConfirmAndBulkSell() throws {
        launch(["-reset", "-seedparts", "-seedstock", "3", "-phase", "build"])

        // bulk sell: one button clears all 3 tier-1 parts
        let bulk = app.buttons["bulk-sell"]
        XCTAssertTrue(bulk.waitForExistence(timeout: 8))
        XCTAssertTrue(waitLabel(bulk, contains: "3", timeout: 3),
                      "bulk button should count the stock, got \(bulk.label)")
        bulk.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Sold 3 stock parts'")).firstMatch
                        .waitForExistence(timeout: 3), "bulk-sell toast should fire")

        // Pro sale: confirm alert carries the fence price, then the part is gone
        let sell = app.buttons["sell-0"] // tier-desc sort: a Pro part is first
        XCTAssertTrue(sell.waitForExistence(timeout: 3))
        let countBefore = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'install-'")).count
        sell.tap()
        let confirm = app.buttons["sell-confirm"].firstMatch // alert + a11y tree duplicate
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "Pro sale should open the confirm")
        shot("sell_confirm")
        confirm.tap()
        let exp = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", countBefore - 1),
            object: app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'install-'")))
        XCTAssertEqual(XCTWaiter.wait(for: [exp], timeout: 3), .completed,
                       "one Pro part should be sold after confirming")
        shot("sell_done")
    }

    /// #73 achievement unlock: first fix fires the First Wrench toast (+ fanfare).
    func testAchievementToast() throws {
        launch(["-reset", "-phase", "garage", "-notut"])
        let prompt = app.staticTexts["garage-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 15))
        XCTAssertTrue(waitLabel(prompt, contains: "Tap a part", timeout: 15))

        XCTAssertTrue(tapFirstEnabled("fix", range: 0...5), "no fixable part")
        XCTAssertTrue(app.staticTexts["🔧 First Wrench — Fix your first part."]
                        .waitForExistence(timeout: 3),
                      "First Wrench achievement toast should fire on the first fix")

        // the gallery from the menu shows it unlocked
        app.buttons["nav-menu"].tap()
        app.buttons["menu-achv"].tap()
        let row = app.staticTexts.matching(NSPredicate(format: "identifier == 'achv-first_fix'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "gallery row should exist")
        shot("achievements_gallery")
    }

    /// #80 what's-new: shows once on a version bump (simulated via -oldversion),
    /// dismiss stamps the version, and it never reappears on the next boot.
    func testWhatsNewOnce() throws {
        // build a save first (newGame stamps the current version)
        launch(["-reset", "-phase", "setup"])
        XCTAssertTrue(app.buttons["start-day1"].waitForExistence(timeout: 5))
        app.buttons["start-day1"].tap()
        XCTAssertTrue(app.buttons["nav-build"].waitForExistence(timeout: 8))
        app.terminate()

        // version bump: the card appears exactly once
        launch(["-oldversion"])
        let card = app.otherElements["whatsnew-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "what's-new card should show on a version bump")
        shot("whats_new")
        app.buttons["whatsnew-dismiss"].tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 3), "dismiss should close the card")
        app.terminate()

        // next boot: stamped — no card
        launch([])
        XCTAssertFalse(card.waitForExistence(timeout: 4), "what's-new must not reappear after stamping")
    }

    /// #10 paint shop: swatch → persisted paint across a relaunch.
    func testPaintPersists() throws {
        launch(["-reset", "-phase", "build"])
        let blue = app.buttons["paint-3B82F6"]
        XCTAssertTrue(blue.waitForExistence(timeout: 8))
        blue.tap()
        XCTAssertEqual(blue.value as? String, "selected", "swatch should read selected after the tap")
        app.terminate()

        launch(["-phase", "build"]) // NO -reset — paint must survive
        XCTAssertTrue(blue.waitForExistence(timeout: 8))
        XCTAssertEqual(blue.value as? String, "selected", "paint must persist across a relaunch")
        shot("paint_shop")
    }

    /// #7 daily challenge: card matches the mulberry32-of-date algorithm exactly,
    /// and finishing the daily stamps the once-per-day bonus line on results.
    func testDailyChallengeDeterminism() throws {
        // expected combo, computed independently (same algorithm as the web)
        let exp = expectedDailyCombo()
        launch(["-reset", "-phase", "garage", "-notut", "-instantfinish"])
        app.buttons["nav-race"].tap()
        let card = app.otherElements["daily-card"]
        XCTAssertTrue(card.waitForExistence(timeout: 8), "daily card should top the track sheet")
        XCTAssertTrue(app.staticTexts[exp.headline].waitForExistence(timeout: 3),
                      "daily card should read \"\(exp.headline)\"")
        shot("daily_card")

        // race the daily → results carry the DAILY RUN ✓ line (and the once-per-day stamp)
        app.buttons["daily-run"].tap()
        XCTAssertTrue(app.staticTexts["race-timer"].waitForExistence(timeout: 5), "race should start")
        let dailyLine = app.staticTexts["results-daily"]
        XCTAssertTrue(dailyLine.waitForExistence(timeout: 25), "results should show DAILY RUN ✓")
        XCTAssertTrue(dailyLine.label.contains("DAILY RUN ✓"), "got \(dailyLine.label)")
        shot("daily_results")
    }

    // MARK: daily-combo reference implementation (mirrors js/data.js dailyChallenge)

    private func expectedDailyCombo() -> (headline: String, trackIdx: Int) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let key = fmt.string(from: Date())
        var a = fnv1a("dailyrun:" + key)
        func r() -> Double {
            a = a &+ 0x6D2B79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
        let trackIdx = Int(r() * 2)
        let rev = r() < 0.5
        let tod = Int(r() * 3)
        let w = r()
        let wx = w < 0.35 ? "RAIN" : w < 0.55 ? "FOG" : "CLEAR"
        let name = trackIdx == 0 ? "Meadow Loop" : "Figure-8 Ridge"
        let tods = ["Day", "Sunset", "Night"]
        return ("\(name)\(rev ? " ⇄" : "") · \(tods[tod]) · \(wx)", trackIdx)
    }

    private func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for u in s.utf16 { h = (h ^ UInt32(u)) &* 16777619 }
        return h
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
