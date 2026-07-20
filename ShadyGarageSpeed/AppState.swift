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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak self] in
            self?.toasts.removeAll { $0.id == t.id }
        }
    }
}

final class AppState: ObservableObject {
    @Published var phase: GamePhase = .menu
    @Published var lastFinish: FinishData?
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
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-reset") {
            UserDefaults.standard.removeObject(forKey: "sgs_save") // fresh state for tests
        }
        game.load() // restore save if present (New Game overwrites on Start)
        game.onSaveFailure = { [weak self] in
            self?.toasts.push("⚠️ Save failed — progress may not persist.", .bad)
        }
        if args.contains("-seedparts") {
            // deterministic inventory for tests: one tier-3 part of each type
            for t in GameState.partTypes { game.inventory.append(game.makePart(t, 3)) }
            game.save()
        }
        raceScene.onFinish = { [weak self] data in
            guard let self else { return }
            self.lastFinish = data
            self.raceChallenge = nil // the challenge is consumed by the run
            if data.challenge?.becameLegend == true { self.showLegendOverlay = true }
            self.phase = .results
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
    }

    // MARK: navigation

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
        raceChallenge = nil
        raceScene.challengeIndex = nil
        phase = .race
        raceScene.startRun()
    }

    /// Pink-slip challenge: race the rival at ladder position `pos` (0–3).
    func startChallenge(_ pos: Int) {
        guard GameState.ladderRival(pos) != nil else { return }
        garageScene.exitPlay()
        raceChallenge = pos
        raceScene.challengeIndex = pos
        phase = .race
        raceScene.startRun()
    }

    func raceAgain() {
        raceChallenge = nil
        raceScene.challengeIndex = nil
        phase = .race
        raceScene.startRun()
    }

    /// Debug deep-link from launch args, e.g. `-phase race` (used for screenshots/testing).
    func applyDebugPhase(_ name: String) {
        switch name {
        case "garage": continueGame()
        case "build":  goBuild()
        case "race":   goRace()
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
        if args.contains("-autodrive") { raceScene.autoDrive = true }
        if args.contains("-ladderwin") { raceScene.ladderWin = true }
        if args.contains("-instantfinish") { raceScene.instantFinish = true }
        if args.contains("-watch") { garageScene.forceWatch = true }
        if args.contains("-nowatch") { garageScene.watchDisabled = true }
        if args.contains("-cop") { garageScene.forceCop = true }
        if args.contains("-debughud") { garageScene.debugHUD = true }
        if let i = args.firstIndex(of: "-heat"), i + 1 < args.count,
           let h = Int(args[i + 1]) {
            game.heat = min(100, max(0, h))
            game.save() // persist so a relaunch sees the same heat
        }
        if let i = args.firstIndex(of: "-arch"), i + 1 < args.count {
            game.forcedArchetype = args[i + 1]
        }
        if let i = args.firstIndex(of: "-phase"), i + 1 < args.count {
            applyDebugPhase(args[i + 1])
        }
        // deep-link a pink-slip race: -phase race -challenge N (after -phase so
        // goRace's challenge reset can't clobber it)
        if let i = args.firstIndex(of: "-challenge"), i + 1 < args.count,
           let pos = Int(args[i + 1]) {
            startChallenge(pos)
        }
        // -paused: freeze the race at the countdown for pause-overlay screenshots
        if args.contains("-paused"), phase == .race {
            raceScene.setPaused(true)
        }
    }
}
