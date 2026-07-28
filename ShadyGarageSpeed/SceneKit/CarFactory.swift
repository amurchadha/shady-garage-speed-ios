// CarFactory.swift — port of cars.js: procedural low-poly vehicle & avatar builders.
// Cars face +Z. Part groups are named ('engine', 'turbo', ...) so tap raycasts can
// walk up the node hierarchy to find the owning part.
import SceneKit

enum CarFactory {

    /// Wheel radius shared by every car (SCNCylinder in the tires group) — used
    /// to convert ground speed into wheel spin (rad = dist / radius).
    static let wheelRadius: Float = 0.42

    // A customer / generic car. Exact dims/positions from web makeCar().
    // bodyStyle: 'sedan' (default) | 'hatch' (shorter, taller rear) | 'truck' (cab + open bed).
    static func makeCar(color: Int = 0xf87171, spoiler: Bool = false, bodyStyle: String = "sedan",
                        tiresTier: Int = 1) -> SCNNode {
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

        // --- tires part group (rims vary by tier: stock gray / sport / pro / elite gold — #11) ---
        let tires = SCNNode(); tires.name = "tires"
        let tireMat = FlatMat.lit(UIColor(rgb: 0x151a22))
        for (i, xz) in [(-0.98, 1.45), (0.98, 1.45), (-0.98, -1.45), (0.98, -1.45)].enumerated() {
            let w = SCNNode(); w.name = "tire\(i)"
            let wheelGeo = SCNCylinder(radius: 0.42, height: 0.34)
            wheelGeo.radialSegmentCount = 10
            wheelGeo.materials = [tireMat]
            let tire = SCNNode(geometry: wheelGeo)
            tire.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            tire.castsShadow = true
            let rimG = SCNNode(); rimG.name = "rim"
            if tiresTier <= 1 {
                let rimGeo = SCNCylinder(radius: 0.2, height: 0.36)
                rimGeo.radialSegmentCount = 8
                rimGeo.materials = [FlatMat.lit(UIColor(rgb: 0x9ca3af))]
                let rim = SCNNode(geometry: rimGeo)
                rim.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                rim.castsShadow = true
                rimG.addChildNode(rim)
            } else {
                // #11 tier rims: hub + spokes on the outer face (web cars.js proportions)
                let accent = tiresTier == 2 ? 0x3b82f6 : tiresTier == 3 ? 0xa855f7 : 0xd4af37
                let spokeC = tiresTier == 4 ? 0xd4af37 : 0x374151
                let face: CGFloat = (xz.0 > 0 ? 1 : -1) * 0.17
                if tiresTier < 4 { // accent hub (elite spokes reach the center instead)
                    let hubGeo = SCNCylinder(radius: 0.09, height: 0.38)
                    hubGeo.radialSegmentCount = 8
                    hubGeo.materials = [FlatMat.lit(UIColor(rgb: accent))]
                    let hub = SCNNode(geometry: hubGeo)
                    hub.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                    hub.castsShadow = true
                    rimG.addChildNode(hub)
                }
                let spokes = tiresTier == 4 ? 6 : 5
                for s in 0..<spokes {
                    let a = CGFloat(s) / CGFloat(spokes) * .pi * 2
                    let sp = boxNode(0.08, 0.34, 0.07, UIColor(rgb: spokeC),
                                     face, CGFloat(cos(a)) * 0.11, CGFloat(sin(a)) * 0.11)
                    sp.eulerAngles = SCNVector3(-Float(a), 0, 0) // radial in the wheel plane
                    sp.castsShadow = true
                    rimG.addChildNode(sp)
                }
                if tiresTier == 3 { rimG.scale = SCNVector3(1.25, 1, 1) } // pro: wider stance
            }
            w.addChildNode(tire)
            w.addChildNode(rimG)
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

        // --- nitrous part group (#8: tank in the trunk area) ---
        let nitrous = SCNNode(); nitrous.name = "nitrous"
        let tankGeo = SCNCylinder(radius: 0.22, height: 0.9)
        tankGeo.radialSegmentCount = 10
        tankGeo.materials = [FlatMat.lit(UIColor(rgb: 0x3b82f6))]
        let tank = SCNNode(geometry: tankGeo)
        tank.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)
        tank.position = SCNVector3(0.45, 0.95, -1.75)
        tank.castsShadow = true
        nitrous.addChildNode(tank)
        nitrous.addChildNode(boxNode(0.1, 0.1, 0.12, UIColor(rgb: 0x93c5fd), 0.45, 0.95, -1.28))

        // --- ecu part group (#9: small box on the dash/firewall) ---
        let ecu = SCNNode(); ecu.name = "ecu"
        ecu.addChildNode(boxNode(0.34, 0.1, 0.24, UIColor(rgb: 0x111827), 0.5, 1.02, 0.62))
        let ledGeo = SCNBox(width: 0.05, height: 0.03, length: 0.05, chamferRadius: 0)
        ledGeo.materials = [FlatMat.emissive(UIColor(rgb: 0x22c55e), 0.8)]
        let led = SCNNode(geometry: ledGeo)
        led.position = SCNVector3(0.42, 1.09, 0.56)
        ecu.addChildNode(led)

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

        for child in [body, cabin, engine, tires, suspension, turbo, exhaust, bodykit, nitrous, ecu, lights] {
            car.addChildNode(child)
        }

        if spoiler {
            let sp = SCNNode(); sp.name = "spoiler"
            sp.addChildNode(boxNode(0.09, 0.32, 0.09, UIColor(rgb: 0x1f2937), -0.62, 1.12, -1.9))
            sp.addChildNode(boxNode(0.09, 0.32, 0.09, UIColor(rgb: 0x1f2937), 0.62, 1.12, -1.9))
            sp.addChildNode(boxNode(1.7, 0.08, 0.45, UIColor(rgb: 0x1f2937), 0, 1.3, -1.95))
            car.addChildNode(sp)
        }

        // body style variants — same 6 named part groups everywhere (web cars.js)
        if bodyStyle == "hatch" {
            // shorter, taller rear
            body.scale = SCNVector3(1, 1.05, 0.88)
            cabin.position.z = -0.62
            cabin.scale = SCNVector3(1, 1.1, 0.82)
            exhaust.position.z += 0.35
            lights.enumerateChildNodes { n, _ in
                if n.position.z < 0 { n.position.z *= 0.85 }
            }
            tires.enumerateChildNodes { w, _ in
                if w.position.z < 0 { w.position.z = -1.2 }
            }
            if let sp = find(car, "spoiler") { sp.position.z += 0.3 }
        } else if bodyStyle == "truck" {
            // cab-only cabin forward + open bed behind
            cabin.position = SCNVector3(0, 1.18, 0.55)
            cabin.scale = SCNVector3(1.08, 1.02, 0.55)
            body.scale = SCNVector3(body.scale.x, body.scale.y, 1.04)
            let bedMat = FlatMat.lit(shade(color, 0.8))
            let bed = SCNNode()
            bed.name = "bed"
            let floorGeo = SCNBox(width: 1.9, height: 0.12, length: 1.9, chamferRadius: 0)
            floorGeo.materials = [bedMat]
            let floorNode = SCNNode(geometry: floorGeo)
            floorNode.position = SCNVector3(0, 0.72, -1.35)
            bed.addChildNode(floorNode)
            for x in [Float(-0.95), Float(0.95)] {
                let wallGeo = SCNBox(width: 0.1, height: 0.5, length: 1.9, chamferRadius: 0)
                wallGeo.materials = [bedMat]
                let wall = SCNNode(geometry: wallGeo)
                wall.position = SCNVector3(x, 0.98, -1.35)
                bed.addChildNode(wall)
            }
            let tailGeo = SCNBox(width: 1.9, height: 0.5, length: 0.1, chamferRadius: 0)
            tailGeo.materials = [bedMat]
            let tail = SCNNode(geometry: tailGeo)
            tail.position = SCNVector3(0, 0.98, -2.28)
            bed.addChildNode(tail)
            car.addChildNode(bed)
        }
        return car
    }

    // The player's custom race car, rebuilt from state each time it changes.
    /// paint (#10): hex override for the body color (nil = chassis default).
    static func makeCustomCar(carState: CarBuild, paint: Int? = nil) -> SCNNode {
        let L = carState.chassis
        let bodyColors = [0, 0x9a5b3c, 0x3b82f6, 0xf97316, 0xa855f7] // per chassis level
        let bodyColor = paint ?? bodyColors[min(L, 4)]
        let parts = carState.parts
        // #11 rims follow the tires tier
        let car = makeCar(color: bodyColor, spoiler: L >= 2, tiresTier: parts.tires?.tier ?? 1)

        // engine tier → block color + size
        if let p = parts.engine, let block = find(car, "engineBlock") {
            block.geometry?.materials = [FlatMat.lit(UIColor(rgb: GameState.tierColors[p.tier]))]
            let s = Float(1 + 0.12 * Double(p.tier))
            block.scale = SCNVector3(s, s, s)
        }
        // turbo / exhaust / bodykit / nitrous / ecu tiers → recolor their meshes
        if let p = parts.turbo      { tintGroup(car, "turbo", GameState.tierColors[p.tier]) }
        if let p = parts.exhaust    { tintGroup(car, "exhaust", GameState.tierColors[p.tier]) }
        if let p = parts.bodykit    { tintGroup(car, "bodykit", GameState.tierColors[p.tier]) }
        if let p = parts.nitrous    { tintGroup(car, "nitrous", GameState.tierColors[p.tier]) } // #8 tank tint
        if let p = parts.ecu        { tintGroup(car, "ecu", GameState.tierColors[p.tier]) }     // #9 box tint
        // L3: lower, sportier accent stripes
        if L >= 3 {
            find(car, "body")?.position.y -= 0.06
            find(car, "cabin")?.position.y -= 0.06
            let s1 = boxNode(0.42, 0.05, 1.3, UIColor(rgb: 0xfacc15), 0, 0.98, 1.5, name: "stripe")
            let s2 = boxNode(0.42, 0.05, 2.0, UIColor(rgb: 0xfacc15), 0, 1.42, -0.35, name: "stripe")
            car.addChildNode(s1)
            car.addChildNode(s2)
        }
        // L4: widebody pods + white racing stripes + #12 underglow
        if L >= 4 {
            car.addChildNode(boxNode(0.3, 0.42, 2.8, UIColor(rgb: 0x1f2937), -1.08, 0.62, 0, name: "widebody"))
            car.addChildNode(boxNode(0.3, 0.42, 2.8, UIColor(rgb: 0x1f2937), 1.08, 0.62, 0, name: "widebody"))
            car.addChildNode(boxNode(0.26, 0.05, 1.3, UIColor(rgb: 0xffffff), -0.3, 0.98, 1.5, name: "stripe"))
            car.addChildNode(boxNode(0.26, 0.05, 1.3, UIColor(rgb: 0xffffff), 0.3, 0.98, 1.5, name: "stripe"))
            car.addChildNode(boxNode(0.26, 0.05, 2.0, UIColor(rgb: 0xffffff), -0.3, 1.42, -0.35, name: "stripe"))
            car.addChildNode(boxNode(0.26, 0.05, 2.0, UIColor(rgb: 0xffffff), 0.3, 1.42, -0.35, name: "stripe"))
            // #12 underglow: soft accent plane + point light (pulsed by the phase loops)
            let ug = SCNNode(); ug.name = "underglow"
            let planeGeo = SCNPlane(width: 3.0, height: 4.8)
            let pm = SCNMaterial()
            pm.lightingModel = .constant
            pm.diffuse.contents = UIColor(rgb: 0xa855f7)
            pm.transparency = 0.28
            pm.blendMode = .add
            pm.writesToDepthBuffer = false
            planeGeo.materials = [pm]
            let plane = SCNNode(geometry: planeGeo)
            plane.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
            plane.position = SCNVector3(0, 0.06, 0)
            plane.name = "uglowPlane"
            ug.addChildNode(plane)
            let ugLight = SCNLight()
            ugLight.type = .omni
            ugLight.color = UIColor(rgb: 0xa855f7)
            ugLight.intensity = 400
            ugLight.attenuationStartDistance = 0.5
            ugLight.attenuationEndDistance = 6
            let lightNode = SCNNode()
            lightNode.light = ugLight
            lightNode.position = SCNVector3(0, 0.35, 0)
            lightNode.name = "uglowLight"
            ug.addChildNode(lightNode)
            car.addChildNode(ug)
        }
        // suspension tier → lower ride height. Runs LAST and covers every
        // add-on (exhaust, stripes, widebody pods) so nothing floats.
        if let p = parts.suspension {
            let dy = Float(0.04 * Double(p.tier))
            let lower: Set<String> = ["body", "cabin", "engine", "spoiler", "lights",
                                      "turbo", "bodykit", "exhaust", "stripe", "widebody"]
            car.enumerateChildNodes { node, _ in
                if let name = node.name, lower.contains(name) { node.position.y -= dy }
            }
        }
        return car
    }

    // Small stylized person for flavor.
    static func makeCharacterAvatar(color: Int = 0x3b82f6) -> SCNNode {
        let g = SCNNode()
        let c = UIColor(rgb: color)
        g.addChildNode(boxNode(0.4, 0.5, 0.26, UIColor(rgb: 0x2f3640), 0, 0.25, 0))
        let torso = boxNode(0.52, 0.55, 0.3, c, 0, 0.78, 0, name: "torso") // leans on flinch
        g.addChildNode(torso)
        g.addChildNode(boxNode(0.12, 0.45, 0.14, c, -0.33, 0.8, 0))
        g.addChildNode(boxNode(0.12, 0.45, 0.14, c, 0.33, 0.8, 0))
        let head = sphereNode(radius: 0.22, color: UIColor(rgb: 0xf2c9a0), segments: 6)
        head.position.y = 1.3
        head.name = "head"
        let capGeo = SCNCone(topRadius: 0.2, bottomRadius: 0.23, height: 0.12)
        capGeo.radialSegmentCount = 8
        capGeo.materials = [FlatMat.lit(c)]
        let cap = SCNNode(geometry: capGeo)
        cap.name = "cap" // follows head tilt
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
