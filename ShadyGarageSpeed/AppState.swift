// AppState.swift — app-wide navigation (phase state machine) + shared services (toasts).
// Mirrors main.js: menu → setup → garage ⇄ build → race → results → garage.
import Foundation
import Combine

// GamePhase lives in GamePhase.swift

struct Toast: Identifiable, Equatable {
    enum Kind { case good, bad, warn, info }
    let id = UUID()
    let text: String
    let kind: Kind
}

final class ToastCenter: ObservableObject {
    @Published private(set) var toasts: [Toast] = []
    @Published private(set) var cashPops: [Toast] = [] // floating "+$X" juice

    func push(_ text: String, _ kind: Toast.Kind = .info) {
        if Thread.isMainThread {
            emit(text, kind)
        } else {
            DispatchQueue.main.async { self.emit(text, kind) }
        }
    }

    private func emit(_ text: String, _ kind: Toast.Kind) {
        let t = Toast(text: text, kind: kind)
        toasts.append(t)
        while toasts.count > 5 { toasts.removeFirst() }
        A11y.announce(text) // VoiceOver reads every toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.toasts.removeAll { $0.id == t.id }
        }
    }

    func pushCash(_ text: String, negative: Bool = false) {
        if Thread.isMainThread {
            emitCash(text, negative)
        } else {
            DispatchQueue.main.async { self.emitCash(text, negative) }
        }
    }

    private func emitCash(_ text: String, _ negative: Bool) {
        let t = Toast(text: text, kind: negative ? .bad : .good)
        cashPops.append(t)
        while cashPops.count > 3 { cashPops.removeFirst() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.cashPops.removeAll { $0.id == t.id }
        }
    }
}

final class AppState: ObservableObject {
    @Published var phase: GamePhase = .menu {
        didSet {
            guard phase != oldValue else { return }
            A11y.screenChanged(phaseDescription) // "screen changed" + phase name
            let sfx = AudioEngine.shared
            // garage radio everywhere except build (bed instead) and race (loop at GO)
            switch phase {
            case .race:
                sfx.buildBed(false)
                sfx.shopAmbience(false)
            case .build:
                sfx.musicStop()       // radio must NOT layer over the build-bay bed
                sfx.buildBed(true)    // #36 hum + sparse clanks
                sfx.shopAmbience(false)
            default:
                sfx.buildBed(false)
                sfx.musicStart("garage")
                sfx.shopAmbience(phase == .garage) // #39 shop sounds under the radio
            }
            // #59 orientation lock follows the phase (Landscape-race mode)
            OrientationLock.inRace = (phase == .race)
            OrientationLock.apply()
        }
    }
    @Published var lastFinish: FinishData?
    /// Pre-race track-select sheet (opened by the garage topbar Race button).
    @Published var showTrackSheet = false
    /// #20 session direction flips (track-select ⇄ per card; not persisted).
    @Published var trackReversed: Set<String> = []
    /// #59 orientation setting mirror so Settings rows repaint on change.
    @Published var orientationMode = OrientationLock.mode
    /// Results photo mode: UI hidden, slow orbit of the parked car (web #25).
    @Published var showPhotoMode = false {
        didSet {
            raceScene.photoMode = showPhotoMode
        }
    }

    /// VoiceOver phase names ("Garage. Day 3." style).
    private var phaseDescription: String {
        switch phase {
        case .menu:    return "Main menu"
        case .setup:   return "New game setup"
        case .garage:  return "Garage. Day \(game.day)."
        case .build:   return "Build bay"
        case .race:    return "Race"
        case .results: return "Race results"
        }
    }
    /// Thermal downshift: true while ProcessInfo.thermalState is .serious/.critical —
    /// SceneKitViews drop to 30fps and disable MSAA until it cools to .nominal/.fair.
    @Published private(set) var thermalLimited = false
    /// Active pink-slip challenge: ladder position (0–3) being raced, nil = normal run.
    @Published var raceChallenge: Int?
    /// One-time 🏆 STREET LEGEND overlay (shown over the results screen).
    @Published var showLegendOverlay = false

    let game = GameState()
    let toasts = ToastCenter()

    lazy var garageScene: GarageScene = GarageScene(game: game, toasts: toasts)
    lazy var buildScene: BuildScene = BuildScene(game: game, toasts: toasts)
    lazy var raceScene: RaceScene = RaceScene(game: game, toasts: toasts)

    init() {
        A11y.observeMotionChanges() // keep the reduce-motion flag live
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-reset") {
            UserDefaults.standard.removeObject(forKey: "sgs_save") // fresh state for tests
        }
        game.load() // restore save if present (New Game overwrites on Start)
        // #70 offline heat decay notice (decay itself applied in game.load())
        if game.offlineCool >= 10 {
            toasts.push("Things cooled off while you were away. (−\(game.offlineCool) heat)", .info)
        }
        game.onSaveFailure = { [weak self] in
            self?.toasts.push("⚠️ Save failed — progress may not persist.", .bad)
        }
        if args.contains("-seedparts") {
            // deterministic inventory for tests: one tier-3 part of each type
            for t in GameState.partTypes { game.inventory.append(game.makePart(t, 3)) }
            game.save()
        }
        if let i = args.firstIndex(of: "-seedstock"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            // deterministic tier-1 stock for bulk-sell tests (#67)
            for k in 0..<n { game.inventory.append(game.makePart(GameState.partTypes[k % GameState.partTypes.count], 1)) }
            game.save()
        }
        raceScene.onFinish = { [weak self] data in
            guard let self else { return }
            self.lastFinish = data
            self.raceChallenge = nil // the challenge is consumed by the run
            if data.reward > 0 || (data.challenge?.win == true) {
                Haptics.cashCascade() // #56 prize payout cascade
            }
            if ProcessInfo.processInfo.arguments.contains("-confetti") {
                self.raceScene.confettiBurst() // debug: force a confetti burst
            }
            if data.challenge?.becameLegend == true {
                self.showLegendOverlay = true
                self.raceScene.confettiBurst() // #26 legend confetti over the results
            }
            // VoiceOver: results + ladder progress
            if let ch = data.challenge {
                if ch.win {
                    if data.challenge?.becameLegend == true {
                        A11y.announce("Pink slip won against \(ch.name). You are the Street Legend!")
                    } else if let next = GameState.ladderRival(self.game.ladder) {
                        A11y.announce("Pink slip won against \(ch.name). Next rival: \(next.name), beat \(String(format: "%.1f", next.time)) seconds.")
                    }
                } else {
                    A11y.announce("Pink slip lost to \(ch.name) by \(String(format: "%.2f", data.lap - ch.target)) seconds.")
                }
            } else {
                A11y.announce("Lap complete, \(String(format: "%.1f", data.lap)) seconds\(data.newBest ? ", new best" : "").")
            }
            self.phase = .results
            // debug: jump straight into photo mode on finish
            if ProcessInfo.processInfo.arguments.contains("-photo") {
                self.enterPhotoMode()
            }
        }
        raceScene.onExit = { [weak self] in
            guard let self else { return }
            self.phase = .garage
            self.garageScene.enterPlay()
        }

        // battery governor: watch the thermal state (fail-safe: starts .nominal on sims)
        let seriousOrWorse = { ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue }
        thermalLimited = seriousOrWorse()
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.thermalLimited = seriousOrWorse()
        }

        AudioEngine.shared.musicStart("garage") // garage radio from the menu

        // #54/#58 deep links (quick action, App Intents) — warm + cold start
        NotificationCenter.default.addObserver(forName: DeepLinkCenter.name, object: nil,
                                               queue: .main) { [weak self] note in
            if let link = note.userInfo?["link"] as? String { self?.handleDeepLink(link) }
        }
        if let link = DeepLinkCenter.pending {
            DeepLinkCenter.pending = nil
            DispatchQueue.main.async { self.handleDeepLink(link) }
        }

        // #52 iCloud save sync (compiled out unless ICLOUD_ENABLED — see project.yml)
        CloudSync.shared.onMerged = { [weak self] in
            guard let self else { return }
            self.game.load() // blob already written by CloudSync; apply it in-memory
            self.toasts.push("Synced from your other device", .good)
        }
        CloudSync.shared.start()

        // #51 Game Center (compiled out unless GAMECENTER_ENABLED — see project.yml)
        GCManager.shared.authenticate()
    }

    /// #54 quick action / #58 App Intent: "track-select" — land in the garage with
    /// the track picker up. Mid-race links are ignored; without a save there is no
    /// car to race, so setup opens instead.
    func handleDeepLink(_ link: String) {
        guard link == "track-select", phase != .race else { return }
        if phase == .menu || phase == .setup {
            guard game.hasSave() else { goSetup(); return }
            continueGame()
        } else if phase != .garage {
            backToGarage()
        }
        goRace() // opens the track-select sheet
    }

    // MARK: navigation

    /// Results 📷: hide the UI and orbit the parked car; tap anywhere to exit.
    func enterPhotoMode() {
        showPhotoMode = true
    }

    func exitPhotoMode() {
        showPhotoMode = false
    }

    /// scenePhase → all scene sims: false freezes integration (no dt spike on
    /// resume) and drops race inputs/audio; true resumes cleanly.
    func setActive(_ active: Bool) {
        garageScene.appActive = active
        buildScene.appActive = active
        raceScene.appActive = active
    }

    func goMenu() {
        garageScene.exitPlay()
        garageScene.setMode(.attract)
        phase = .menu
    }

    func goSetup() {
        garageScene.setMode(.attract)
        phase = .setup
    }

    func startNewGame(_ name: String, _ charIndex: Int) {
        game.newGame(name, charIndex)
        phase = .garage
        garageScene.enterPlay()
        toasts.push("Welcome, \(game.playerName)! Your garage is open.", .good)
    }

    func continueGame() {
        phase = .garage
        garageScene.enterPlay()
    }

    func goBuild() {
        garageScene.exitPlay()
        buildScene.refreshCustomCar()
        phase = .build
    }

    func backToGarage() {
        phase = .garage
        garageScene.enterPlay()
    }

    func goRace() {
        garageScene.exitPlay()
        showTrackSheet = true // topbar Race opens the track-select sheet first
    }

    /// Direct race start on a track (sheet row, debug deep-link, race again).
    func startRaceOnTrack(_ i: Int) {
        showTrackSheet = false
        raceChallenge = nil
        raceScene.challengeIndex = nil
        raceScene.trackIndex = i
        raceScene.reversed = trackReversed.contains(GameState.tracks[i].id) // #20
        phase = .race
        raceScene.startRun()
    }

    /// Pink-slip challenge: race the rival at ladder position `pos` (0–3).
    /// Rival challenges always stay on Classic, driven forwards.
    func startChallenge(_ pos: Int) {
        guard GameState.ladderRival(pos) != nil else { return }
        garageScene.exitPlay()
        raceChallenge = pos
        raceScene.challengeIndex = pos
        raceScene.trackIndex = 0
        raceScene.reversed = false // #20 rivals race the classic direction
        phase = .race
        raceScene.startRun()
    }

    func raceAgain() {
        showTrackSheet = false
        raceChallenge = nil
        raceScene.challengeIndex = nil
        phase = .race
        raceScene.startRun() // keeps the current track + direction
    }

    /// Debug deep-link from launch args, e.g. `-phase race` (used for screenshots/testing).
    func applyDebugPhase(_ name: String) {
        switch name {
        case "garage": continueGame()
        case "build":  goBuild()
        case "race":   startRaceOnTrack(0) // debug races go straight to Classic
        case "setup":  goSetup()
        default:       break
        }
    }

    /// Full debug arg set: -phase <p> -tod day|sunset|night -rain on|off -autodrive
    /// -challenge N -ladderwin -instantfinish -arch <t> -watch -nowatch
    func applyDebugArgs(_ args: [String]) {
        if let i = args.firstIndex(of: "-tod"), i + 1 < args.count {
            switch args[i + 1] {
            case "day":    raceScene.forcedTOD = 0
            case "sunset": raceScene.forcedTOD = 1
            case "night":  raceScene.forcedTOD = 2
            default:       break
            }
        }
        if let i = args.firstIndex(of: "-rain"), i + 1 < args.count {
            let v = args[i + 1]
            raceScene.forcedRain = v == "on" ? true : v == "off" ? false : nil
        }
        // -wx rain|fog|clear: force weather (fog = 4th condition, headlights on)
        if let i = args.firstIndex(of: "-wx"), i + 1 < args.count {
            raceScene.forcedWX = args[i + 1]
        }
        if args.contains("-autodrive") { raceScene.autoDrive = true }
        if args.contains("-ladderwin") { raceScene.ladderWin = true }
        if args.contains("-instantfinish") { raceScene.instantFinish = true }
        if args.contains("-watch") { garageScene.forceWatch = true }
        if args.contains("-nowatch") { garageScene.watchDisabled = true }
        if args.contains("-cop") { garageScene.forceCop = true }
        if let i = args.firstIndex(of: "-entrance"), i + 1 < args.count {
            garageScene.forceEntrance = args[i + 1] // normal|reverse|swing (screenshots)
        }
        if args.contains("-debughud") { garageScene.debugHUD = true }
        if args.contains("-audio-debug") { AudioEngine.audioDebug = true }
        if let i = args.firstIndex(of: "-streak"), i + 1 < args.count,
           let n = Int(args[i + 1]) {
            game.cleanStreak = max(0, n) // #15 seed for tests/screenshots
        }
        // #20 pre-flip every track card (and the debug race) — screenshots
        if args.contains("-reverse") { trackReversed = Set(GameState.tracks.map(\.id)) }
        if let i = args.firstIndex(of: "-heat"), i + 1 < args.count,
           let h = Int(args[i + 1]) {
            game.heat = min(100, max(0, h))
            game.save() // persist so a relaunch sees the same heat
        }
        if let i = args.firstIndex(of: "-cash"), i + 1 < args.count,
           let c = Int(args[i + 1]) {
            game.cash = max(0, c)
            game.save()
        }
        // -contract <type> <minTier>: seed an active contracts-board order (tests)
        if let i = args.firstIndex(of: "-contract"), i + 2 < args.count,
           let tier = Int(args[i + 2]) {
            game.contract = Contract(type: args[i + 1], minTier: tier, deadline: game.day + 3,
                                     reward: Int((60.0 * Double(tier) * 2.2).rounded()))
            game.save()
        }
        if let i = args.firstIndex(of: "-arch"), i + 1 < args.count {
            game.forcedArchetype = args[i + 1]
        }
        // -track N (with -phase race): race the Nth track instead of Classic
        var debugTrack = 0
        if let i = args.firstIndex(of: "-track"), i + 1 < args.count, let t = Int(args[i + 1]) {
            debugTrack = t
        }
        if let i = args.firstIndex(of: "-phase"), i + 1 < args.count {
            if args[i + 1] == "race" {
                startRaceOnTrack(debugTrack)
            } else {
                applyDebugPhase(args[i + 1])
            }
        }
        // deep-link a pink-slip race: -phase race -challenge N (after -phase so
        // goRace's challenge reset can't clobber it)
        if let i = args.firstIndex(of: "-challenge"), i + 1 < args.count,
           let pos = Int(args[i + 1]) {
            startChallenge(pos)
        }
        // -tracksheet / -settingsheet: open those sheets directly (screenshots)
        if args.contains("-tracksheet") { showTrackSheet = true }
        if args.contains("-golden") { game.forcedGolden = true }
        // -notut: suppress the first-run tutorial (screenshots)
        if args.contains("-notut") { game.tutorialSeen = true }
        // -paused: freeze the race at the countdown for pause-overlay screenshots
        if args.contains("-paused"), phase == .race {
            raceScene.setPaused(true)
        }
        // -lugnut: show the Daily Lugnut card immediately (screenshots)
        if args.contains("-lugnut") {
            garageScene.debugLugnut()
        }
    }
}
