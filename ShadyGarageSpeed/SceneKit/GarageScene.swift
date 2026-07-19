// GarageScene.swift — port of garage.js: customer loop, tap inspection, fix/steal,
// suspicion/rage, heat consequences (cop visit + raid), attract/play cameras.
import SceneKit
import UIKit

final class GarageScene: SceneController {
    enum Mode { case attract, play }

    let game: GameState
    let toasts: ToastCenter
    private let sfx = AudioEngine.shared

    // MARK: published to SwiftUI (always set on main)
    @Published private(set) var customer: Customer?
    @Published private(set) var jobState = "idle" // idle|arriving|inspect|leaving|angry
    @Published private(set) var jobTotal = 0
    @Published private(set) var jobActions = 0
    @Published private(set) var jobSteals = 0
    @Published private(set) var prompt = ""
    @Published var selectedPart: String?
    @Published var pendingStealIndex: Int?  // non-nil → SwiftUI shows the steal minigame
    @Published var showCopModal = false
    @Published private(set) var canBribe = false

    // MARK: internals
    private var mode: Mode = .attract
    /// Set by GarageView in portrait: nudge the play camera down so the parked
    /// customer car sits above the bottom-sheet job panel.
    var portraitFraming = false
    private var customerCar: SCNNode?
    private var partMats: [String: [SCNMaterial]] = [:]
    private var elapsed: Double = 0
    private var attractAngle: Double = 0.6
    private var shakeT: Double = 0
    private var rage90Warned = false
    private var avatars: [SCNNode] = []

    private struct GStep { var to: SCNVector3; var yaw: Float; var dur: Double }
    private struct Tween {
        var car: SCNNode
        var steps: [GStep]
        var onDone: () -> Void
        var t: Double = 0
        var from: SCNVector3? = nil
        var fromYaw: Float = 0
    }
    private var drive: Tween?

    init(game: GameState, toasts: ToastCenter) {
        self.game = game
        self.toasts = toasts
        super.init()
        cameraNode.camera?.fieldOfView = 55
        scene.background.contents = UIColor(rgb: 0x8fd3ff)
        scene.fogColor = UIColor(rgb: 0x8fd3ff)
        scene.fogStartDistance = 55
        scene.fogEndDistance = 150
        buildScene()
    }

    // MARK: - scene construction (port of buildScene())

    private func addBox(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ hex: Int,
                        _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, casts: Bool = true) {
        scene.rootNode.addChildNode(boxNode(w, h, d, UIColor(rgb: hex), x, y, z, casts: casts))
    }

    private func buildScene() {
        // lights
        let hemi = SCNNode()
        let hemiL = SCNLight()
        hemiL.type = .ambient
        hemiL.color = UIColor(rgb: 0xd9f2ff)
        hemiL.intensity = 650
        hemi.light = hemiL
        scene.rootNode.addChildNode(hemi)

        let target = SCNNode()
        scene.rootNode.addChildNode(target)

        let sun = SCNNode()
        let sunL = SCNLight()
        sunL.type = .directional
        sunL.color = UIColor(rgb: 0xfff1d6)
        sunL.intensity = 1100
        sunL.castsShadow = true
        sunL.orthographicScale = 34
        sunL.zNear = 1
        sunL.zFar = 90
        sunL.shadowRadius = 2
        sun.light = sunL
        sun.position = SCNVector3(20, 28, 14)
        let look = SCNLookAtConstraint(target: target)
        sun.constraints = [look]
        scene.rootNode.addChildNode(sun)

        let interior = SCNNode()
        let intL = SCNLight()
        intL.type = .omni
        intL.color = UIColor(rgb: 0xffd9a0)
        intL.intensity = 700
        intL.attenuationStartDistance = 2
        intL.attenuationEndDistance = 24
        interior.light = intL
        interior.position = SCNVector3(0, 4, -7)
        scene.rootNode.addChildNode(interior)

        // ground + concrete slab
        addBox(170, 0.5, 170, 0x7cc466, 0, -0.25, 0, casts: false)
        addBox(30, 0.14, 38, 0xb5b0a8, 0, -0.05, 3, casts: false)

        // garage building (open front faces +z)
        let WALL = 0xd97757, ROOF = 0x5b6470
        addBox(18, 5, 0.4, WALL, 0, 2.5, -12)          // back wall
        addBox(0.4, 5, 10, WALL, -9, 2.5, -7)          // left wall
        addBox(0.4, 5, 10, WALL, 9, 2.5, -7)           // right wall
        addBox(19, 0.5, 11.5, ROOF, 0, 5.25, -7.25)    // roof
        addBox(18, 1.1, 0.4, WALL, 0, 4.55, -2)        // header above opening
        addBox(1.2, 5, 0.4, WALL, -8.4, 2.5, -2)       // front pillars
        addBox(1.2, 5, 0.4, WALL, 8.4, 2.5, -2)
        addBox(17.2, 4.4, 0.1, 0xc2603f, 0, 2.3, -11.75) // interior back wall tint

        // sign board + text
        addBox(11, 1.7, 0.3, 0x1f2937, 0, 6.25, -1.9)
        let signGeo = SCNText(string: "SHADY GARAGE", extrusionDepth: 0.06)
        signGeo.font = UIFont.systemFont(ofSize: 1.0, weight: .heavy)
        signGeo.flatness = 0.05
        signGeo.materials = [FlatMat.emissive(UIColor(rgb: 0xffd23f), 0.35)]
        let sign = SCNNode(geometry: signGeo)
        let (sMin, sMax) = signGeo.boundingBox
        sign.pivot = SCNMatrix4MakeTranslation((sMin.x + sMax.x) / 2, (sMin.y + sMax.y) / 2, 0)
        let signScale = 10.2 / max(sMax.x - sMin.x, 0.001)
        sign.scale = SCNVector3(signScale, signScale, signScale)
        sign.position = SCNVector3(0, 6.25, -1.72)
        scene.rootNode.addChildNode(sign)

        // road + dashes
        addBox(130, 0.1, 7, 0x4a4f57, 0, 0.0, 25, casts: false)
        for x in stride(from: -60.0, through: 60.0, by: 8.0) {
            addBox(2.2, 0.12, 0.28, 0xfacc15, x, 0.06, 25, casts: false)
        }

        // workbench
        addBox(3.2, 0.18, 1.1, 0x8b5a2b, -6.3, 0.98, -10.4)
        for xz in [(-7.7, -10.8), (-4.9, -10.8), (-7.7, -10.0), (-4.9, -10.0)] {
            addBox(0.14, 0.9, 0.14, 0x5b3a1e, xz.0, 0.45, xz.1)
        }
        addBox(0.5, 0.3, 0.4, 0x9ca3af, -6.9, 1.2, -10.4)
        addBox(0.4, 0.22, 0.3, 0xef4444, -5.7, 1.16, -10.3)

        // red toolbox stack
        addBox(1.2, 0.55, 0.75, 0xdc2626, -7.6, 0.28, -7.6)
        addBox(1.05, 0.45, 0.65, 0xb91c1c, -7.6, 0.78, -7.6)
        addBox(0.9, 0.35, 0.55, 0xdc2626, -7.6, 1.18, -7.6)

        // tire stack
        for i in 0..<4 {
            let t = cylNode(radius: 0.5, height: 0.34, color: UIColor(rgb: 0x1f2937), segments: 12)
            t.position = SCNVector3(6.8, 0.17 + Float(i) * 0.34, -9.5)
            scene.rootNode.addChildNode(t)
        }

        // barrels + crates
        for item in [(0x3b82f6, 7.9, -3.2), (0xf59e0b, 8.3, -4.6)] {
            let b = cylNode(radius: 0.55, height: 1.1, color: UIColor(rgb: item.0), segments: 10)
            b.position = SCNVector3(Float(item.1), 0.55, Float(item.2))
            scene.rootNode.addChildNode(b)
        }
        addBox(1, 1, 1, 0xa16207, -12, 0.5, 2.5)
        addBox(0.8, 0.8, 0.8, 0xca8a04, -11, 0.4, 4.2)

        // plants outside
        for xz in [(-11.5, 6.5), (11.5, 6.5), (-11.5, -1), (11.5, -1)] {
            addBox(0.7, 0.5, 0.7, 0xb45309, xz.0, 0.25, xz.1)
            let bush = coneNode(topRadius: 0, bottomRadius: 0.75, height: 1.5,
                                color: UIColor(rgb: 0x2f9e44), segments: 8)
            bush.position = SCNVector3(Float(xz.0), 1.2, Float(xz.1))
            scene.rootNode.addChildNode(bush)
        }

        // the 4 friends hanging out
        let spots: [(Float, Float, Float)] = [(-6.5, -4.5, 0.6), (-5.2, -3, 1.8), (-6.8, -1.2, 0.2), (-4.2, -5, 2.6)]
        for (i, f) in GameState.friends.enumerated() {
            let a = CarFactory.makeCharacterAvatar(color: f.color)
            a.position = SCNVector3(spots[i].0, 0, spots[i].1)
            a.eulerAngles = SCNVector3(0, spots[i].2, 0)
            scene.rootNode.addChildNode(a)
            avatars.append(a)
        }
    }

    // MARK: - drive tween (port of processDrive)

    private func smooth(_ k: Double) -> Double { k * k * (3 - 2 * k) }
    private func shortAngle(_ a: Float) -> Float {
        var a = a
        while a > Float.pi { a -= Float.pi * 2 }
        while a < -Float.pi { a += Float.pi * 2 }
        return a
    }

    private func processDrive(_ dt: Double) {
        guard var d = drive else { return }
        guard let s = d.steps.first else {
            drive = nil
            d.onDone()
            return
        }
        if d.from == nil {
            d.from = d.car.position
            d.fromYaw = d.car.eulerAngles.y
            d.t = 0
        }
        d.t += dt / s.dur
        let k = Float(smooth(min(1, d.t)))
        let f = d.from!
        d.car.position = SCNVector3(f.x + (s.to.x - f.x) * k,
                                    f.y + (s.to.y - f.y) * k,
                                    f.z + (s.to.z - f.z) * k)
        d.car.eulerAngles.y = d.fromYaw + shortAngle(s.yaw - d.fromYaw) * k
        if d.t >= 1 {
            d.car.position = s.to
            d.car.eulerAngles.y = s.yaw
            d.steps.removeFirst()
            d.from = nil
        }
        drive = d
    }

    // MARK: - customer flow (port of garage.js flow)

    private func startNextCustomer() {
        // heat consequences trigger on arrival, before the next car pulls in
        if game.heat >= 100 {
            raid()
        } else if game.heat >= 70 && Double.random(in: 0..<1) < 0.35 {
            copVisit()
            return // modal callbacks continue the flow
        }
        spawnCustomer()
    }

    private func raid() {
        let n = (game.inventory.count + 1) / 2 // ceil(half)
        for _ in 0..<n where !game.inventory.isEmpty {
            game.inventory.remove(at: Int.random(in: 0..<game.inventory.count))
        }
        game.heat = 30
        game.save()
        sfx.fail()
        Haptics.notify(.error)
        if n > 0 {
            toasts.push("🚨 RAID! Cops seized \(n) of your parts.", .bad)
        } else {
            toasts.push("🚨 RAID! Cops found nothing — this time.", .warn)
        }
    }

    private func copVisit() {
        prompt = "🚨 Cops are sniffing around…"
        canBribe = game.cash >= 200
        showCopModal = true
        Haptics.notify(.warning)
    }

    func copBribe() {
        showCopModal = false
        game.cash -= 200
        game.heat = max(0, game.heat - 50)
        game.save()
        toasts.push("Bribe paid. The cops wander off. -$200", .warn)
        spawnCustomer()
    }

    func copLayLow() {
        showCopModal = false
        game.heat = max(0, game.heat - 40)
        game.day += 1
        game.save()
        toasts.push("You lay low. The customer drives away.", .warn)
        startNextCustomer()
    }

    private func spawnCustomer() {
        let c = game.generateCustomer()
        customer = c
        let car = CarFactory.makeCar(color: c.color)
        car.position = SCNVector3(38, 0, 24)
        car.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)
        scene.rootNode.addChildNode(car)
        customerCar = car
        cachePartMats()
        jobState = "arriving"
        jobTotal = 0
        jobActions = 0
        jobSteals = 0
        selectedPart = nil
        rage90Warned = false
        prompt = "Customer pulling in…"
        drive = Tween(car: car, steps: [
            GStep(to: SCNVector3(1.5, 0, 23.5), yaw: -Float.pi / 2, dur: 1.5),
            GStep(to: SCNVector3(0.5, 0, 5), yaw: Float.pi, dur: 1.1),
            GStep(to: SCNVector3(0, 0, -4.5), yaw: 0, dur: 1.0),
        ], onDone: { [weak self] in
            DispatchQueue.main.async {
                self?.jobState = "inspect"
                self?.prompt = "Tap a part on the car, or use the job panel."
            }
        })
    }

    private func driveOut(_ happy: Bool) {
        jobState = "leaving"
        prompt = happy ? "Another satisfied customer!" : "…"
        clearHighlights()
        selectedPart = nil
        guard let car = customerCar else { startNextCustomer(); return }
        drive = Tween(car: car, steps: [
            GStep(to: SCNVector3(0, 0, 6), yaw: 0, dur: happy ? 1.2 : 0.7),
            GStep(to: SCNVector3(-2, 0, 23.5), yaw: -Float.pi / 2, dur: happy ? 1.1 : 0.7),
            GStep(to: SCNVector3(-40, 0, 23.5), yaw: -Float.pi / 2, dur: happy ? 1.7 : 1.0),
        ], onDone: { [weak self] in
            guard let self else { return }
            car.removeFromParentNode()
            if self.customerCar === car { self.customerCar = nil }
            DispatchQueue.main.async {
                self.customer = nil
                self.startNextCustomer()
            }
        })
    }

    private func rage() {
        jobState = "angry"
        shakeT = 0.9
        sfx.fail()
        prompt = "The customer noticed something!"
        selectedPart = nil
        clearHighlights()
    }

    // MARK: - part highlight

    private func cachePartMats() {
        partMats = [:]
        guard let car = customerCar else { return }
        for part in GameState.partTypes {
            var mats: [SCNMaterial] = []
            if let g = car.childNode(withName: part, recursively: true) {
                if let geo = g.geometry { mats.append(contentsOf: geo.materials) }
                g.enumerateChildNodes { node, _ in
                    if let geo = node.geometry { mats.append(contentsOf: geo.materials) }
                }
            }
            partMats[part] = mats
        }
    }

    private func setPartEmissive(_ part: String, _ hex: Int, _ intensity: CGFloat) {
        guard let mats = partMats[part] else { return }
        for m in mats {
            m.emission.contents = UIColor(rgb: hex)
            m.emission.intensity = intensity
        }
    }

    private func clearHighlights() {
        for p in GameState.partTypes { setPartEmissive(p, 0x000000, 0) }
    }

    private func refreshHighlights() {
        for p in GameState.partTypes {
            if p == selectedPart {
                setPartEmissive(p, 0x22d3ee, 0.35 + 0.15 * CGFloat(sin(elapsed * 7)))
            } else {
                setPartEmissive(p, 0x000000, 0)
            }
        }
    }

    // MARK: - tap raycast (called from SceneKitView tap recognizer, main thread)

    func handleTap(_ point: CGPoint, _ view: SCNView) {
        guard mode == .play, jobState == "inspect", let car = customerCar, drive == nil else { return }
        let hits = view.hitTest(point, options: [SCNHitTestOption.rootNode: car])
        var found: String?
        for h in hits {
            var node: SCNNode? = h.node
            while let n = node {
                if let name = n.name, GameState.partTypes.contains(name) { found = name; break }
                node = n.parent
            }
            if found != nil { break }
        }
        guard let p = found else { return }
        selectedPart = p
        sfx.click()
    }

    // MARK: - public job actions (called from GarageView)

    func fixPart(_ i: Int) {
        guard jobState == "inspect", var c = customer, c.parts.indices.contains(i) else { return }
        var p = c.parts[i]
        guard p.needsService, !p.fixed else { return }
        let amount = 40 + 25 * p.tier + game.fixBonus
        jobTotal += amount
        jobActions += 1
        p.fixed = true
        c.parts[i] = p
        customer = c
        sfx.success()
        toasts.push("Fixed \(GameState.partLabels[p.type] ?? p.type) +$\(amount)", .good)
        game.save()
    }

    func stealPart(_ i: Int) {
        guard jobState == "inspect", let c = customer, c.parts.indices.contains(i), !c.parts[i].stolen else { return }
        pendingStealIndex = i
    }

    func resolveSteal(_ zone: String) { // "green" | "yellow" | "red"
        guard let i = pendingStealIndex else { return }
        pendingStealIndex = nil
        guard jobState == "inspect", var c = customer, c.parts.indices.contains(i) else { return }
        var p = c.parts[i]
        guard !p.stolen else { return }
        let mult = game.suspMult
        if zone == "red" {
            addSuspicion(35 * mult)
            toasts.push("Caught fiddling! Suspicion way up.", .bad)
            Haptics.notify(.error)
        } else {
            let tier = p.tier
            game.inventory.append(game.makePart(p.type, tier))
            p.tier = 1
            p.needsService = false
            p.fixed = true
            p.stolen = true
            c.parts[i] = p
            customer = c
            jobActions += 1
            jobSteals += 1
            game.heat = min(100, game.heat + 6 + 2 * tier)
            let gain = (zone == "green" ? Double(12 + 6 * tier) : Double(25 + 8 * tier)) * mult
            addSuspicion(gain)
            sfx.cash()
            Haptics.notify(.success)
            toasts.push("Stole \(GameState.tierNames[tier]) \(GameState.partLabels[p.type] ?? p.type)!",
                        zone == "green" ? .good : .warn)
        }
        game.save()
        if game.suspicion >= 100 && jobState == "inspect" { rage() }
    }

    private func addSuspicion(_ v: Double) {
        let before = game.suspicion
        game.suspicion = min(100, Int((Double(game.suspicion) + v).rounded()))
        if game.suspicion >= 90 && before < 90 && !rage90Warned {
            rage90Warned = true
            toasts.push("Customer is very suspicious…", .warn)
        }
    }

    func finishJob() {
        guard jobState == "inspect", jobActions >= 1 else { return }
        let payment = Int((Double(jobTotal) * game.payMult).rounded())
        game.cash += payment
        game.customersServed += 1
        game.day += 1
        game.suspicion = 0
        if jobSteals == 0 { game.heat = max(0, game.heat - 8) } // clean job cools things down
        game.save()
        sfx.cash()
        toasts.push("Job done! +$\(payment)", .good)
        driveOut(true)
    }

    // MARK: - phase interface

    func setMode(_ m: Mode) { mode = m }

    func enterPlay() {
        mode = .play
        if customer == nil {
            startNextCustomer()
        } else if jobState == "inspect" {
            prompt = "Tap a part on the car, or use the job panel."
        }
    }

    func exitPlay() {
        selectedPart = nil
    }

    // MARK: - frame update (render thread)

    override func update(dt: TimeInterval) {
        elapsed += dt

        if mode == .attract {
            attractAngle += dt * 0.09
            let r = Float(25)
            cameraNode.position = SCNVector3(
                Float(cos(attractAngle)) * r,
                9 + Float(sin(elapsed * 0.4)) * 0.6,
                Float(sin(attractAngle)) * r + 2)
            cameraNode.look(at: SCNVector3(0, 2.5, -4))
        } else {
            if portraitFraming {
                // portrait: aim at the driveway so the car at (0,0,-4.5) rides
                // ~9° above frame center, clear of the bottom-sheet job panel
                cameraNode.position = SCNVector3(
                    8.5 + Float(sin(elapsed * 0.5)) * 0.18,
                    7.6 + Float(sin(elapsed * 0.33)) * 0.12,
                    12.2 + Float(cos(elapsed * 0.42)) * 0.15)
                cameraNode.look(at: SCNVector3(0, -3, -4.5))
            } else {
                cameraNode.position = SCNVector3(
                    11 + Float(sin(elapsed * 0.5)) * 0.18,
                    7 + Float(sin(elapsed * 0.33)) * 0.12,
                    10 + Float(cos(elapsed * 0.42)) * 0.15)
                cameraNode.look(at: SCNVector3(0, 1.3, -4.5))
            }
        }

        processDrive(dt)

        // angry shake
        if shakeT > 0, let car = customerCar {
            shakeT -= dt
            car.position.x = Float((Double.random(in: 0..<1) - 0.5) * 0.16)
            if shakeT <= 0 {
                car.position.x = 0
                DispatchQueue.main.async {
                    self.game.day += 1
                    self.game.suspicion = 0
                    self.game.save()
                    self.toasts.push("Customer left furious! No pay.", .bad)
                    self.driveOut(false)
                }
            }
        }

        // idle friend bobbing
        for (i, a) in avatars.enumerated() {
            a.position.y = Float(abs(sin(elapsed * 2 + Double(i) * 1.7)) * 0.05)
        }

        // selection pulse on customer car
        if mode == .play && jobState == "inspect" && customerCar != nil && drive == nil {
            refreshHighlights()
        }
    }
}
