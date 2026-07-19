// BuildScene.swift — port of build.js: custom car on a turntable lift,
// chassis upgrades, part install/sell.
import SceneKit

final class BuildScene: SceneController {
    let game: GameState
    let toasts: ToastCenter
    private let sfx = AudioEngine.shared

    private var turntable = SCNNode()
    private var customCar: SCNNode?
    private var elapsed: Double = 0
    /// Set by BuildView in portrait: lift the car above the bottom-sheet panel.
    var portraitFraming = false

    init(game: GameState, toasts: ToastCenter) {
        self.game = game
        self.toasts = toasts
        super.init()
        cameraNode.camera?.fieldOfView = 50
        scene.background.contents = UIColor(rgb: 0x2a2f3a)
        scene.fogColor = UIColor(rgb: 0x2a2f3a)
        scene.fogStartDistance = 30
        scene.fogEndDistance = 90
        buildScene()
    }

    private func addBox(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ hex: Int,
                        _ x: CGFloat, _ y: CGFloat, _ z: CGFloat, casts: Bool = true) {
        scene.rootNode.addChildNode(boxNode(w, h, d, UIColor(rgb: hex), x, y, z, casts: casts))
    }

    private func buildScene() {
        let hemi = SCNNode()
        let hemiL = SCNLight()
        hemiL.type = .ambient
        hemiL.color = UIColor(rgb: 0xcfe4ff)
        hemiL.intensity = 600
        hemi.light = hemiL
        scene.rootNode.addChildNode(hemi)

        let target = SCNNode()
        scene.rootNode.addChildNode(target)

        let key = SCNNode()
        let keyL = SCNLight()
        keyL.type = .directional
        keyL.color = UIColor(rgb: 0xffe9c4)
        keyL.intensity = 1000
        keyL.castsShadow = true
        keyL.orthographicScale = 14
        keyL.zNear = 1
        keyL.zFar = 40
        keyL.shadowRadius = 2
        key.light = keyL
        key.position = SCNVector3(8, 12, 6)
        key.constraints = [SCNLookAtConstraint(target: target)]
        scene.rootNode.addChildNode(key)

        let work = SCNNode()
        let workL = SCNLight()
        workL.type = .omni
        workL.color = UIColor(rgb: 0xffd9a0)
        workL.intensity = 800
        workL.attenuationStartDistance = 2
        workL.attenuationEndDistance = 26
        work.light = workL
        work.position = SCNVector3(0, 5.5, 2.5)
        scene.rootNode.addChildNode(work)

        // floor + walls
        addBox(26, 0.4, 20, 0x565c66, 0, -0.2, 0, casts: false)
        addBox(26, 7, 0.4, 0x3f4652, 0, 3.5, -9)
        addBox(0.4, 7, 20, 0x39404b, -13, 3.5, 0)
        addBox(0.4, 7, 20, 0x39404b, 13, 3.5, 0)

        // pegboard with tools on the back wall
        addBox(9, 3.6, 0.15, 0x9a6b3f, -4, 3.1, -8.7)
        let toolColors = [0xd1d5db, 0xef4444, 0xf59e0b, 0x3b82f6, 0x9ca3af]
        for i in 0..<12 {
            let c = toolColors[i % toolColors.count]
            let tx = -7.6 + Double(i % 6) * 1.4
            let ty = 2.2 + Double(i / 6) * 1.4
            addBox(0.16 + Double(i % 3) * 0.1, 0.7, 0.1, c, tx, ty, -8.58)
        }

        // shelves with boxes (right)
        let boxColors = [0xa16207, 0x475569, 0x7c2d12]
        for s in 0..<3 {
            addBox(4.6, 0.16, 1.3, 0x6b4f2a, 9.8, 1.4 + Double(s) * 1.5, -6.5)
            for b in 0..<3 {
                addBox(0.9, 0.7, 0.9, boxColors[(s + b) % 3],
                       8.4 + Double(b) * 1.4, 1.83 + Double(s) * 1.5, -6.5)
            }
        }

        // spare tire stack (left)
        for i in 0..<5 {
            let t = cylNode(radius: 0.55, height: 0.36, color: UIColor(rgb: 0x1f2937), segments: 12)
            t.position = SCNVector3(-9.5, 0.18 + Float(i) * 0.36, -5.5)
            scene.rootNode.addChildNode(t)
        }

        // oil drum + crate
        let drum = cylNode(radius: 0.55, height: 1.1, color: UIColor(rgb: 0x0ea5e9), segments: 10)
        drum.position = SCNVector3(-10.5, 0.55, 2)
        scene.rootNode.addChildNode(drum)
        addBox(1.1, 1.1, 1.1, 0xa16207, 10.5, 0.55, 3)

        // hanging work lamps (emissive cones)
        for xz in [(-2.5, 1.0), (2.5, 1.0)] {
            let lampGeo = SCNCone(topRadius: 0, bottomRadius: 0.5, height: 0.6)
            lampGeo.radialSegmentCount = 10
            lampGeo.materials = [FlatMat.emissive(UIColor(rgb: 0xffd9a0), 0.5)]
            let lamp = SCNNode(geometry: lampGeo)
            lamp.position = SCNVector3(Float(xz.0), 5.6, Float(xz.1))
            scene.rootNode.addChildNode(lamp)
            addBox(0.05, 1.0, 0.05, 0x1f2937, xz.0, 6.4, xz.1)
        }

        // hydraulic lift + turntable platform
        addBox(0.5, 2.4, 0.5, 0xf59e0b, -2.6, 1.2, 0)
        addBox(0.5, 2.4, 0.5, 0xf59e0b, 2.6, 1.2, 0)
        let base = cylNode(radius: 3.8, height: 0.18, color: UIColor(rgb: 0x4b5563), segments: 28)
        base.position.y = 0.09
        scene.rootNode.addChildNode(base)
        let platform = cylNode(radius: 3.3, height: 0.28, color: UIColor(rgb: 0x6b7280), segments: 28)
        platform.position.y = 0.45
        turntable.addChildNode(platform)
        scene.rootNode.addChildNode(turntable)
    }

    func refreshCustomCar() {
        customCar?.removeFromParentNode()
        let car = CarFactory.makeCustomCar(carState: game.car)
        car.position.y = 0.59
        turntable.addChildNode(car)
        customCar = car
    }

    // MARK: - public actions (port of build.js actions)

    func upgradeChassis() {
        let L = game.car.chassis
        guard let cost = game.chassisCost(L) else {
            toasts.push("Chassis is maxed out!", .warn)
            return
        }
        guard game.cash >= cost else {
            toasts.push("Not enough cash (need $\(cost))", .bad)
            sfx.fail()
            return
        }
        game.cash -= cost
        game.car.chassis += 1
        game.save()
        refreshCustomCar()
        sfx.success()
        toasts.push("Upgraded to \(GameState.chassisNames[game.car.chassis])!", .good)
    }

    func installPart(_ id: String) {
        guard let idx = game.inventory.firstIndex(where: { $0.id == id }) else { return }
        let part = game.inventory[idx]
        let replaced = game.car.parts[part.type]
        game.inventory.remove(at: idx)
        if let replaced { game.inventory.append(replaced) }
        game.car.parts[part.type] = part
        game.save()
        refreshCustomCar()
        sfx.success()
        toasts.push("Installed \(GameState.partLabels[part.type] ?? part.type)", .good)
    }

    func sellPart(_ id: String) {
        guard let idx = game.inventory.firstIndex(where: { $0.id == id }) else { return }
        let part = game.inventory[idx]
        let price = Int((Double(game.partSellPrice(part.tier)) * game.sellMult).rounded())
        game.inventory.remove(at: idx)
        game.cash += price
        game.save()
        refreshCustomCar()
        sfx.cash()
        toasts.push("Sold \(GameState.partLabels[part.type] ?? part.type) +$\(price)", .good)
    }

    // MARK: - frame update

    override func update(dt: TimeInterval) {
        elapsed += dt
        turntable.eulerAngles.y += Float(dt) * 0.35
        if portraitFraming {
            // portrait: aim below the car so it rides above the bottom-sheet panel
            cameraNode.position = SCNVector3(
                8.5 + Float(sin(elapsed * 0.4)) * 0.2,
                5.6 + Float(sin(elapsed * 0.3)) * 0.12,
                9.8 + Float(cos(elapsed * 0.35)) * 0.15)
            cameraNode.look(at: SCNVector3(0, -1.5, 0))
        } else {
            cameraNode.position = SCNVector3(
                7.5 + Float(sin(elapsed * 0.4)) * 0.2,
                4.8 + Float(sin(elapsed * 0.3)) * 0.12,
                8.5 + Float(cos(elapsed * 0.35)) * 0.15)
            cameraNode.look(at: SCNVector3(0, 1.2, 0))
        }
    }
}
