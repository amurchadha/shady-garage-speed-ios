// CarFactory.swift — port of cars.js: procedural low-poly vehicle & avatar builders.
// Cars face +Z. Part groups are named ('engine', 'turbo', ...) so tap raycasts can
// walk up the node hierarchy to find the owning part.
import SceneKit

enum CarFactory {

    /// Wheel radius shared by every car (SCNCylinder in the tires group) — used
    /// to convert ground speed into wheel spin (rad = dist / radius).
    static let wheelRadius: Float = 0.42

    // A customer / generic car. Exact dims/positions from web makeCar().
    static func makeCar(color: Int = 0xf87171, spoiler: Bool = false) -> SCNNode {
        let car = SCNNode()
        car.name = "car"
        let bodyColor = UIColor(rgb: color)

        let body = boxNode(1.9, 0.55, 4.3, bodyColor, 0, 0.72, 0, name: "body")
        let cabin = boxNode(1.55, 0.5, 2.0, UIColor(rgb: 0x273449), 0, 1.2, -0.35, name: "cabin")

        // --- engine part group ---
        let engine = SCNNode(); engine.name = "engine"
        let scoop = boxNode(1.2, 0.12, 1.1, shade(color, 0.82), 0, 1.04, 1.35, name: "hood")
        let block = boxNode(0.55, 0.3, 0.6, UIColor(rgb: 0x8b939e), 0, 1.22, 1.35, name: "engineBlock")
        engine.addChildNode(scoop)
        engine.addChildNode(block)

        // --- tires part group ---
        let tires = SCNNode(); tires.name = "tires"
        let tireMat = FlatMat.lit(UIColor(rgb: 0x151a22))
        let rimMat = FlatMat.lit(UIColor(rgb: 0x9ca3af))
        for (i, xz) in [(-0.98, 1.45), (0.98, 1.45), (-0.98, -1.45), (0.98, -1.45)].enumerated() {
            let w = SCNNode(); w.name = "tire\(i)"
            let wheelGeo = SCNCylinder(radius: 0.42, height: 0.34)
            wheelGeo.radialSegmentCount = 10
            wheelGeo.materials = [tireMat]
            let tire = SCNNode(geometry: wheelGeo)
            tire.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            tire.castsShadow = true
            let rimGeo = SCNCylinder(radius: 0.2, height: 0.36)
            rimGeo.radialSegmentCount = 8
            rimGeo.materials = [rimMat]
            let rim = SCNNode(geometry: rimGeo)
            rim.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            rim.castsShadow = true
            rim.name = "rim"
            w.addChildNode(tire)
            w.addChildNode(rim)
            w.position = SCNVector3(Float(xz.0), 0.42, Float(xz.1))
            tires.addChildNode(w)
        }

        // --- suspension part group ---
        let suspension = SCNNode(); suspension.name = "suspension"
        let under = boxNode(1.7, 0.2, 3.9, UIColor(rgb: 0x2f3640), 0, 0.32, 0, name: "underbody")
        let axleMat = FlatMat.lit(UIColor(rgb: 0x2f3640))
        for z in [Float(1.45), Float(-1.45)] {
            let axleGeo = SCNCylinder(radius: 0.07, height: 2.0)
            axleGeo.radialSegmentCount = 6
            axleGeo.materials = [axleMat]
            let axle = SCNNode(geometry: axleGeo)
            axle.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            axle.position = SCNVector3(0, 0.42, z)
            axle.castsShadow = true
            suspension.addChildNode(axle)
        }
        suspension.addChildNode(under)

        // --- turbo part group (snail + piping on the engine) ---
        let turbo = SCNNode(); turbo.name = "turbo"
        let snailGeo = SCNCylinder(radius: 0.16, height: 0.3)
        snailGeo.radialSegmentCount = 8
        snailGeo.materials = [FlatMat.lit(UIColor(rgb: 0x8b939e))]
        let snail = SCNNode(geometry: snailGeo)
        snail.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        snail.position = SCNVector3(0.45, 1.18, 1.35)
        snail.castsShadow = true
        let tPipe = boxNode(0.12, 0.12, 0.5, UIColor(rgb: 0x6b7280), 0.45, 1.08, 1.05)
        turbo.addChildNode(snail)
        turbo.addChildNode(tPipe)

        // --- exhaust part group (twin pipes at the rear) ---
        let exhaust = SCNNode(); exhaust.name = "exhaust"
        let pipeMat = FlatMat.lit(UIColor(rgb: 0x9ca3af))
        for x in [Float(-0.5), Float(0.5)] {
            let pipeGeo = SCNCone(topRadius: 0.09, bottomRadius: 0.11, height: 0.5)
            pipeGeo.radialSegmentCount = 8
            pipeGeo.materials = [pipeMat]
            let p = SCNNode(geometry: pipeGeo)
            p.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
            p.position = SCNVector3(x, 0.55, -2.25)
            p.castsShadow = true
            exhaust.addChildNode(p)
        }

        // --- bodykit part group (front lip + side skirts) ---
        let bodykit = SCNNode(); bodykit.name = "bodykit"
        bodykit.addChildNode(boxNode(1.95, 0.14, 0.3, UIColor(rgb: 0x4b5563), 0, 0.42, 2.15))
        bodykit.addChildNode(boxNode(0.12, 0.16, 2.6, UIColor(rgb: 0x4b5563), -1.02, 0.42, 0))
        bodykit.addChildNode(boxNode(0.12, 0.16, 2.6, UIColor(rgb: 0x4b5563), 1.02, 0.42, 0))

        // --- lights ---
        let lights = SCNNode(); lights.name = "lights"
        for xz in [(-0.6, 2.14), (0.6, 2.14)] {
            let geo = SCNBox(width: 0.3, height: 0.13, length: 0.08, chamferRadius: 0)
            geo.materials = [FlatMat.emissive(UIColor(rgb: 0xfde68a), 0.5)]
            let h = SCNNode(geometry: geo)
            h.position = SCNVector3(Float(xz.0), 0.78, Float(xz.1))
            lights.addChildNode(h)
        }
        for xz in [(-0.6, -2.14), (0.6, -2.14)] {
            let geo = SCNBox(width: 0.3, height: 0.13, length: 0.08, chamferRadius: 0)
            geo.materials = [FlatMat.emissive(UIColor(rgb: 0xef4444), 0.4)]
            let t = SCNNode(geometry: geo)
            t.position = SCNVector3(Float(xz.0), 0.78, Float(xz.1))
            lights.addChildNode(t)
        }

        for child in [body, cabin, engine, tires, suspension, turbo, exhaust, bodykit, lights] {
            car.addChildNode(child)
        }

        if spoiler {
            let sp = SCNNode(); sp.name = "spoiler"
            sp.addChildNode(boxNode(0.09, 0.32, 0.09, UIColor(rgb: 0x1f2937), -0.62, 1.12, -1.9))
            sp.addChildNode(boxNode(0.09, 0.32, 0.09, UIColor(rgb: 0x1f2937), 0.62, 1.12, -1.9))
            sp.addChildNode(boxNode(1.7, 0.08, 0.45, UIColor(rgb: 0x1f2937), 0, 1.3, -1.95))
            car.addChildNode(sp)
        }
        return car
    }

    // The player's custom race car, rebuilt from state each time it changes.
    static func makeCustomCar(carState: CarBuild) -> SCNNode {
        let L = carState.chassis
        let bodyColors = [0, 0x9a5b3c, 0x3b82f6, 0xf97316, 0xa855f7] // per chassis level
        let car = makeCar(color: bodyColors[min(L, 4)], spoiler: L >= 2)
        let parts = carState.parts

        // engine tier → block color + size
        if let p = parts.engine, let block = find(car, "engineBlock") {
            block.geometry?.materials = [FlatMat.lit(UIColor(rgb: GameState.tierColors[p.tier]))]
            let s = Float(1 + 0.12 * Double(p.tier))
            block.scale = SCNVector3(s, s, s)
        }
        // turbo / exhaust / bodykit tiers → recolor their meshes
        if let p = parts.turbo      { tintGroup(car, "turbo", GameState.tierColors[p.tier]) }
        if let p = parts.exhaust    { tintGroup(car, "exhaust", GameState.tierColors[p.tier]) }
        if let p = parts.bodykit    { tintGroup(car, "bodykit", GameState.tierColors[p.tier]) }
        // tires tier → rim color
        if let p = parts.tires, let tires = find(car, "tires") {
            let rimColor = FlatMat.lit(UIColor(rgb: GameState.tierColors[p.tier]))
            tires.enumerateChildNodes { node, _ in
                if node.name == "rim" { node.geometry?.materials = [rimColor] }
            }
        }
        // suspension tier → lower ride height
        if let p = parts.suspension {
            let dy = Float(0.04 * Double(p.tier))
            for n in ["body", "cabin", "engine", "spoiler", "lights", "turbo", "bodykit"] {
                if let o = find(car, n) { o.position.y -= dy }
            }
        }
        // L3: lower, sportier accent stripes
        if L >= 3 {
            find(car, "body")?.position.y -= 0.06
            find(car, "cabin")?.position.y -= 0.06
            let s1 = boxNode(0.42, 0.05, 1.3, UIColor(rgb: 0xfacc15), 0, 0.98, 1.5, name: "stripe")
            let s2 = boxNode(0.42, 0.05, 2.0, UIColor(rgb: 0xfacc15), 0, 1.42, -0.35, name: "stripe")
            car.addChildNode(s1)
            car.addChildNode(s2)
        }
        // L4: widebody pods + white racing stripes
        if L >= 4 {
            car.addChildNode(boxNode(0.3, 0.42, 2.8, UIColor(rgb: 0x1f2937), -1.08, 0.62, 0))
            car.addChildNode(boxNode(0.3, 0.42, 2.8, UIColor(rgb: 0x1f2937), 1.08, 0.62, 0))
            car.addChildNode(boxNode(0.26, 0.05, 1.3, UIColor(rgb: 0xffffff), -0.3, 0.98, 1.5))
            car.addChildNode(boxNode(0.26, 0.05, 1.3, UIColor(rgb: 0xffffff), 0.3, 0.98, 1.5))
            car.addChildNode(boxNode(0.26, 0.05, 2.0, UIColor(rgb: 0xffffff), -0.3, 1.42, -0.35))
            car.addChildNode(boxNode(0.26, 0.05, 2.0, UIColor(rgb: 0xffffff), 0.3, 1.42, -0.35))
        }
        return car
    }

    // Small stylized person for flavor.
    static func makeCharacterAvatar(color: Int = 0x3b82f6) -> SCNNode {
        let g = SCNNode()
        let c = UIColor(rgb: color)
        g.addChildNode(boxNode(0.4, 0.5, 0.26, UIColor(rgb: 0x2f3640), 0, 0.25, 0))
        g.addChildNode(boxNode(0.52, 0.55, 0.3, c, 0, 0.78, 0))
        g.addChildNode(boxNode(0.12, 0.45, 0.14, c, -0.33, 0.8, 0))
        g.addChildNode(boxNode(0.12, 0.45, 0.14, c, 0.33, 0.8, 0))
        let head = sphereNode(radius: 0.22, color: UIColor(rgb: 0xf2c9a0), segments: 6)
        head.position.y = 1.3
        let capGeo = SCNCone(topRadius: 0.2, bottomRadius: 0.23, height: 0.12)
        capGeo.radialSegmentCount = 8
        capGeo.materials = [FlatMat.lit(c)]
        let cap = SCNNode(geometry: capGeo)
        cap.position.y = 1.47
        cap.castsShadow = true
        g.addChildNode(head)
        g.addChildNode(cap)
        return g
    }

    // MARK: - lookup helpers

    static func find(_ root: SCNNode, _ name: String) -> SCNNode? {
        root.childNode(withName: name, recursively: true)
    }

    private static func tintGroup(_ car: SCNNode, _ name: String, _ hex: Int) {
        guard let g = find(car, name) else { return }
        let m = FlatMat.lit(UIColor(rgb: hex))
        g.enumerateChildNodes { node, _ in
            if node.geometry != nil { node.geometry?.materials = [m] }
        }
        if g.geometry != nil { g.geometry?.materials = [m] }
    }
}
