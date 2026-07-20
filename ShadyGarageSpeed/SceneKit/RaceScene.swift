// RaceScene.swift — port of race.js: closed-loop time trial with arcade physics,
// Catmull-Rom track, day/night + rain conditions, NOS boost, lap detection, minimap.
import SceneKit
import UIKit

struct ChallengeResult {
    let name: String      // rival raced
    let target: Double    // their lap time to beat
    let win: Bool
    let margin: Double    // target - lap (positive = won by this much)
    let prizeType: String
    let prizeTier: Int
    let purse: Int
    let becameLegend: Bool // this win completed the ladder
}

struct FinishData {
    let lap: Double
    let best: Double
    let value: Int
    let reward: Int
    let newBest: Bool
    var challenge: ChallengeResult? = nil
}

final class RaceScene: SceneController {
    let game: GameState
    let toasts: ToastCenter
    private let sfx = AudioEngine.shared

    static let SAMPLES = 800
    static let ROAD_HALF: Float = 8      // road is 16 wide
    static let BARRIER_LAT: Float = 10.5 // soft wall

    // MARK: run phase (defect fix: owned by the render thread, SwiftUI gets a
    // read-only mirror — the countdown→GO transition can then fire exactly once)
    private enum RunPhase { case idle, count, racing, finished }
    /// Guards `phase`, the input flags, and other state shared main ⇄ render.
    private let stateLock = NSRecursiveLock()
    private var phase: RunPhase = .idle
    /// Read-only mirror of `phase` for SwiftUI/tests. Written on main only.
    @Published private(set) var runPhase = "idle" // idle|count|racing|finished
    @Published private(set) var countdownText: String?
    @Published private(set) var raceTimerText = "00:00.000"
    @Published private(set) var raceSpeedKmh = 0
    @Published private(set) var nosMeterInt = 100
    @Published private(set) var conditionsText = ""
    @Published private(set) var challengeText: String? = nil // pink-slip HUD banner
    @Published private(set) var minimapTrack: [CGPoint] = []
    @Published private(set) var minimapStartTick = (CGPoint.zero, CGPoint.zero)
    @Published private(set) var minimapPlayer = CGPoint(x: 0.5, y: 0.5)

    /// Set `phase` + publish the mirror. Call under stateLock.
    private func setPhaseLocked(_ p: RunPhase) {
        phase = p
        let s: String
        switch p {
        case .idle: s = "idle"
        case .count: s = "count"
        case .racing: s = "racing"
        case .finished: s = "finished"
        }
        DispatchQueue.main.async { self.runPhase = s }
    }

    // inputs (set by RaceView hold buttons)
    var inputUp = false
    var inputDown = false
    var inputLeft = false
    var inputRight = false
    var inputNos = false

    // callbacks (set by AppState)
    var onFinish: ((FinishData) -> Void)?
    var onExit: (() -> Void)?

    // MARK: track data
    private var centers: [SIMD2<Float>] = []  // (x, z)
    private var tangents: [SIMD2<Float>] = []
    private var startYaw: Float = 0
    private var mapMinX: Float = 0, mapMinZ: Float = 0, mapRange: Float = 1

    // MARK: conditions (day/night + weather)
    private struct TOD {
        let name: String
        let sky: Int
        let fogNear: CGFloat, fogFar: CGFloat
        let hemi: CGFloat
        let hemiSky: Int
        let sun: CGFloat
        let sunColor: Int
        let sunPos: SIMD3<Float>
        let ground: Int
        let road: Int
    }
    private static let tods: [TOD] = [
        TOD(name: "DAY",    sky: 0x7ec8f7, fogNear: 130, fogFar: 460, hemi: 0.95, hemiSky: 0xbfe9ff, sun: 1.15, sunColor: 0xffffff, sunPos: [30, 45, 20],   ground: 0x71c15e, road: 0x40454d),
        TOD(name: "SUNSET", sky: 0xf2916d, fogNear: 110, fogFar: 420, hemi: 0.65, hemiSky: 0xffc9a3, sun: 1.0,  sunColor: 0xffb070, sunPos: [50, 15, -25],  ground: 0x67994e, road: 0x3d4148),
        TOD(name: "NIGHT",  sky: 0x0e1830, fogNear: 90,  fogFar: 380, hemi: 0.32, hemiSky: 0x33415e, sun: 0.28, sunColor: 0x8fa8ff, sunPos: [-25, 45, 10],  ground: 0x2e4a30, road: 0x2b2f36),
    ]
    private var todIndex = 0
    private var raining = false
    private var sunOffset = SIMD3<Float>(30, 45, 20)
    /// Debug overrides via launch args: -tod day|sunset|night, -rain on|off.
    var forcedTOD: Int? = nil
    var forcedRain: Bool? = nil
    /// Debug auto-drive via launch arg -autodrive: holds gas, steers to the centerline.
    var autoDrive = false
    /// Pink-slip mode: ladder position (0–3) set by AppState.startChallenge.
    var challengeIndex: Int? = nil
    /// Debug `-ladderwin`: the challenged rival's time is treated as 999s (auto-win).
    var ladderWin = false
    /// Debug `-instantfinish`: finishLap fires ~1s after GO (deterministic tests).
    var instantFinish = false
    /// User pause (⏸ HUD button): sim frozen, timer held, loops silenced.
    @Published private(set) var paused = false

    /// Freeze/resume the sim. Only valid during countdown/racing (not the finish roll).
    func setPaused(_ p: Bool) {
        stateLock.lock()
        if p, phase != .count, phase != .racing {
            stateLock.unlock()
            return
        }
        simPaused = p
        let resumeBoost = !p && boosting
        let resumeEngine = !p && phase == .racing
        stateLock.unlock()
        DispatchQueue.main.async { self.paused = p }
        if p {
            sfx.nos(false)
            Haptics.nosRumble(false)
            sfx.engineSound(false)
        } else {
            if resumeEngine { sfx.engineSound(true) }
            if resumeBoost { sfx.nos(true); Haptics.nosRumble(true) }
        }
    }

    // MARK: scene nodes
    private var carMesh: SCNNode?
    private var flames: [SCNNode] = []
    private let lampGroup = SCNNode()
    private let rainGroup = SCNNode()
    private var rainDrops: [SCNNode] = []
    private var clouds: [(node: SCNNode, x: Float, y: Float, z: Float, spd: Float)] = []
    private let groundMat = FlatMat.lit(UIColor(rgb: 0x71c15e))
    private let roadMat = FlatMat.lit(UIColor(rgb: 0x40454d))
    private let hemiLight = SCNLight()
    private let dirLight = SCNLight()
    private let dirLightNode = SCNNode()
    private let sunTarget = SCNNode()

    // MARK: run state
    private var stats = Stats(speed: 0, accel: 0, handling: 0)
    private var maxSpd: Float = 40
    private var pos = SIMD2<Float>(0, 0)
    private var yaw: Float = 0
    private var speed: Float = 0
    private var countT: Double = 0
    private var lastShown = -1
    private var goT: Double = 0
    private var raceT: Double = 0
    private var finishT: Double = 0
    private var finishFired = false
    private var finishData: FinishData?
    private var lastIdx = 0
    private var prevIdx = 0 // for the wrong-way direction check on the mid checkpoint
    private var lastFrac: Double = 0
    private var passedMid = false
    private var offTrack = false
    private var wasOff = false
    private var camPos = SCNVector3(0, 4.2, -10)
    private var camFov: CGFloat = 62
    private var nosMeter: Float = 100
    private var boosting = false
    private var nosLockout = false   // hit empty while held → locked until released & >15
    private var wallCooldown: Double = 0
    private var publishT: Double = 0
    private var wheels: [SCNNode] = [] // tire0..3, front two steer
    private var wheelSpin: Float = 0
    /// Pink-slip ghost: translucent rival car pacing the target lap time.
    private var ghost: SCNNode?
    private var ghostTime: Double = 0

    init(game: GameState, toasts: ToastCenter) {
        self.game = game
        self.toasts = toasts
        super.init()
        cameraNode.camera?.fieldOfView = 62
        cameraNode.camera?.zFar = 1200
        // HDR + bloom for the race camera (lamps/flames glow at night)
        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.bloomIterationCount = 2
        cameraNode.camera?.bloomThreshold = 0.8
        cameraNode.camera?.bloomIntensity = 0.2
        buildTrack()
        buildMinimapData()
        buildScene()
    }

    // MARK: - Catmull-Rom track (three.js 'catmullrom' closed, tension 0.6)

    private static func hermiteCR(_ p0: SIMD2<Double>, _ p1: SIMD2<Double>,
                                  _ p2: SIMD2<Double>, _ p3: SIMD2<Double>,
                                  tension: Double, w: Double) -> SIMD2<Double> {
        let t1 = (p2 - p0) * tension
        let t2 = (p3 - p1) * tension
        let w2 = w * w, w3 = w2 * w
        let c2 = -3 * p1 + 3 * p2 - 2 * t1 - t2
        let c3 = 2 * p1 - 2 * p2 + t1 + t2
        return p1 + t1 * w + c2 * w2 + c3 * w3
    }

    private func buildTrack() {
        let pts: [SIMD2<Double>] = [
            [0, -128], [60, -123], [111, -94], [132, -43], [119, 9],
            [128, 60], [94, 102], [43, 128], [-9, 119], [-68, 128],
            [-119, 94], [-132, 34], [-119, -26], [-77, -68], [-34, -102],
        ]
        let l = pts.count
        let tension = 0.6
        func evalCurve(_ t: Double) -> SIMD2<Double> {
            var p = Double(l) * t
            if p >= Double(l) { p -= Double(l) }
            let intPoint = Int(floor(p))
            let w = p - Double(intPoint)
            let i1 = intPoint % l
            let i0 = (i1 - 1 + l) % l
            let i2 = (i1 + 1) % l
            let i3 = (i1 + 2) % l
            return Self.hermiteCR(pts[i0], pts[i1], pts[i2], pts[i3], tension: tension, w: w)
        }
        // arc-length table with 200 divisions (matches three.js getSpacedPoints)
        let divs = 200
        var lengths = [Double](repeating: 0, count: divs + 1)
        var prev = evalCurve(0)
        var total: Double = 0
        for i in 1...divs {
            let p = evalCurve(Double(i) / Double(divs))
            total += Double(simd_distance(p, prev))
            lengths[i] = total
            prev = p
        }
        var sampled: [SIMD2<Float>] = []
        sampled.reserveCapacity(Self.SAMPLES)
        for i in 0..<Self.SAMPLES {
            let target = total * Double(i) / Double(Self.SAMPLES)
            var lo = 0, hi = divs
            while lo < hi {
                let mid = (lo + hi) / 2
                if lengths[mid] < target { lo = mid + 1 } else { hi = mid }
            }
            let i1 = max(1, lo)
            let l0 = lengths[i1 - 1], l1 = lengths[i1]
            let f = l1 > l0 ? (target - l0) / (l1 - l0) : 0
            let t = Double(i1 - 1) / Double(divs) + (1.0 / Double(divs)) * f
            let p = evalCurve(t)
            sampled.append(SIMD2<Float>(Float(p.x), Float(p.y)))
        }
        centers = sampled
        tangents = (0..<Self.SAMPLES).map { i in
            let a = centers[(i + 1) % Self.SAMPLES]
            let b = centers[(i - 1 + Self.SAMPLES) % Self.SAMPLES]
            return simd_normalize(a - b)
        }
        startYaw = atan2(tangents[0].x, tangents[0].y) // atan2(tx, tz)
    }

    private func buildMinimapData() {
        var minX = Float.infinity, maxX = -Float.infinity
        var minZ = Float.infinity, maxZ = -Float.infinity
        for c in centers {
            minX = min(minX, c.x); maxX = max(maxX, c.x)
            minZ = min(minZ, c.y); maxZ = max(maxZ, c.y)
        }
        mapMinX = minX; mapMinZ = minZ
        mapRange = max(maxX - minX, maxZ - minZ)
        if mapRange == 0 { mapRange = 1 }
        minimapTrack = centers.map { mapPoint($0) }
        let p0 = mapPoint(centers[0])
        let p4 = mapPoint(centers[4])
        minimapStartTick = (p0, CGPoint(x: (p0.x + p4.x) / 2, y: (p0.y + p4.y) / 2))
    }

    private func mapPoint(_ c: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(12 + (c.x - mapMinX) / mapRange * 116) / 140,
                y: CGFloat(12 + (c.y - mapMinZ) / mapRange * 116) / 140)
    }

    // MARK: - scene construction

    private func normalOf(_ t: SIMD2<Float>) -> SIMD2<Float> { SIMD2<Float>(-t.y, t.x) }

    /// Clone `template` per transform (SceneKit lacks InstancedMesh; clones share geometry).
    private func scatter(_ template: SCNNode, _ transforms: [(SIMD3<Float>, Float, Float)], into parent: SCNNode) {
        for (pos, yaw, scale) in transforms {
            let c = template.flattenedClone()
            c.position = SCNVector3(pos.x, pos.y, pos.z)
            c.eulerAngles = SCNVector3(0, yaw, 0)
            c.scale = SCNVector3(scale, scale, scale)
            parent.addChildNode(c)
        }
    }

    private func buildScene() {
        // lights
        hemiLight.type = .ambient
        hemiLight.color = UIColor(rgb: 0xbfe9ff)
        hemiLight.intensity = 950
        let hemiNode = SCNNode()
        hemiNode.light = hemiLight
        scene.rootNode.addChildNode(hemiNode)

        dirLight.type = .directional
        dirLight.color = UIColor(rgb: 0xffffff)
        dirLight.intensity = 1150
        dirLight.castsShadow = true
        dirLight.orthographicScale = 45
        dirLight.zNear = 1
        dirLight.zFar = 160
        dirLight.shadowRadius = 2
        dirLightNode.light = dirLight
        dirLightNode.position = SCNVector3(30, 45, 20)
        scene.rootNode.addChildNode(sunTarget)
        dirLightNode.constraints = [SCNLookAtConstraint(target: sunTarget)]
        scene.rootNode.addChildNode(dirLightNode)

        scene.background.contents = UIColor(rgb: 0x7ec8f7)
        scene.fogColor = UIColor(rgb: 0x7ec8f7)
        scene.fogStartDistance = 130
        scene.fogEndDistance = 460

        // ground
        let groundGeo = SCNPlane(width: 1200, height: 1200)
        groundGeo.materials = [groundMat]
        let ground = SCNNode(geometry: groundGeo)
        ground.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        ground.position.y = -0.05
        scene.rootNode.addChildNode(ground)

        // road ribbon (non-indexed triangle list, two tris per sample)
        var verts: [SCNVector3] = []
        verts.reserveCapacity(Self.SAMPLES * 6)
        for i in 0..<Self.SAMPLES {
            let j = (i + 1) % Self.SAMPLES
            let n0 = normalOf(tangents[i])
            let n1 = normalOf(tangents[j])
            let L0 = centers[i] + n0 * Self.ROAD_HALF
            let R0 = centers[i] - n0 * Self.ROAD_HALF
            let L1 = centers[j] + n1 * Self.ROAD_HALF
            let R1 = centers[j] - n1 * Self.ROAD_HALF
            let y: Float = 0.02
            verts.append(SCNVector3(L0.x, y, L0.y)); verts.append(SCNVector3(R0.x, y, R0.y)); verts.append(SCNVector3(L1.x, y, L1.y))
            verts.append(SCNVector3(R0.x, y, R0.y)); verts.append(SCNVector3(R1.x, y, R1.y)); verts.append(SCNVector3(L1.x, y, L1.y))
        }
        let vsrc = SCNGeometrySource(vertices: verts)
        let up = SCNVector3(0, 1, 0)
        let nsrc = SCNGeometrySource(normals: [SCNVector3](repeating: up, count: verts.count))
        roadMat.isDoubleSided = true
        // NOTE: must use 4-byte indices — the array-based element init with 8-byte
        // Int indices is invalid (bytesPerIndex supports 1/2/4) and the mesh never renders.
        var indices = (0..<UInt32(verts.count)).map { $0 }
        let indexData = Data(bytes: &indices, count: indices.count * MemoryLayout<UInt32>.size)
        let element = SCNGeometryElement(data: indexData,
                                         primitiveType: .triangles,
                                         primitiveCount: verts.count / 3,
                                         bytesPerIndex: MemoryLayout<UInt32>.size)
        let roadGeo = SCNGeometry(sources: [vsrc, nsrc], elements: [element])
        roadGeo.materials = [roadMat]
        let road = SCNNode(geometry: roadGeo)
        road.castsShadow = false
        scene.rootNode.addChildNode(road)

        // center dashed line
        let dashTemplate = boxNode(0.35, 0.05, 2.4, UIColor(rgb: 0xf8fafc), casts: false)
        var dashT: [(SIMD3<Float>, Float, Float)] = []
        let dashCount = Self.SAMPLES / 14
        for k in 0..<dashCount {
            let i = k * 14
            dashT.append((SIMD3<Float>(centers[i].x, 0.06, centers[i].y),
                          atan2(tangents[i].x, tangents[i].y), 1))
        }
        scatter(dashTemplate, dashT, into: scene.rootNode)

        // red/white edge barriers (alternating)
        let redTemplate = boxNode(0.5, 1.0, 2.6, UIColor(rgb: 0xef4444), casts: false)
        let whiteTemplate = boxNode(0.5, 1.0, 2.6, UIColor(rgb: 0xf8fafc), casts: false)
        var redT: [(SIMD3<Float>, Float, Float)] = []
        var whiteT: [(SIMD3<Float>, Float, Float)] = []
        var k = 0
        var i = 0
        while i < Self.SAMPLES {
            let n = normalOf(tangents[i])
            let yawB = atan2(tangents[i].x, tangents[i].y)
            for side in [Float(1), Float(-1)] {
                let p = SIMD3<Float>(centers[i].x + n.x * 9.3 * side, 0.5,
                                     centers[i].y + n.y * 9.3 * side)
                if k % 2 == 0 { redT.append((p, yawB, 1)) } else { whiteT.append((p, yawB, 1)) }
            }
            i += 6
            k += 1
        }
        scatter(redTemplate, redT, into: scene.rootNode)
        scatter(whiteTemplate, whiteT, into: scene.rootNode)

        // start/finish gantry at t=0
        let gantry = SCNNode()
        for x in [Float(-9.6), Float(9.6)] {
            let p = boxNode(0.6, 6, 0.6, UIColor(rgb: 0x1f2937), CGFloat(x), 3, 0)
            gantry.addChildNode(p)
        }
        gantry.addChildNode(boxNode(20, 1.4, 0.6, UIColor(rgb: 0xff5d3b), 0, 5.8, 0))
        for s in 0..<10 { // checker strip on the banner
            let c: Int = s % 2 == 1 ? 0x111827 : 0xf8fafc
            gantry.addChildNode(boxNode(1, 0.5, 0.66, UIColor(rgb: c), CGFloat(-4.5 + Float(s)), 5.35, 0, casts: false))
        }
        gantry.position = SCNVector3(centers[0].x, 0, centers[0].y)
        gantry.eulerAngles = SCNVector3(0, startYaw, 0)
        scene.rootNode.addChildNode(gantry)

        // trees, placed away from the road
        var treePts: [SIMD2<Float>] = []
        var guardN = 0
        while treePts.count < 64 && guardN < 600 {
            guardN += 1
            let x = (Float.random(in: 0..<1) - 0.5) * 370
            let z = (Float.random(in: 0..<1) - 0.5) * 370
            var ok = true
            var si = 0
            while si < Self.SAMPLES {
                let dx = centers[si].x - x, dz = centers[si].y - z
                if dx * dx + dz * dz < 22 * 22 { ok = false; break }
                si += 8
            }
            if ok { treePts.append(SIMD2<Float>(x, z)) }
        }
        let trunkGeo = SCNCone(topRadius: 0.28, bottomRadius: 0.42, height: 3)
        trunkGeo.radialSegmentCount = 6
        trunkGeo.materials = [FlatMat.lit(UIColor(rgb: 0x8b5a2b))]
        let trunkTemplate = SCNNode(geometry: trunkGeo)
        trunkTemplate.castsShadow = true
        let canopyGeo = SCNSphere(radius: 2.3)
        canopyGeo.segmentCount = 6
        canopyGeo.materials = [FlatMat.lit(UIColor(rgb: 0x2f9e44))]
        let canopyTemplate = SCNNode(geometry: canopyGeo)
        canopyTemplate.castsShadow = true
        var trunkT: [(SIMD3<Float>, Float, Float)] = []
        var canopyT: [(SIMD3<Float>, Float, Float)] = []
        for tp in treePts {
            let s = 0.8 + Float.random(in: 0..<1) * 0.6
            let yawT = Float.random(in: 0..<Float.pi)
            trunkT.append((SIMD3<Float>(tp.x, 1.5 * s, tp.y), yawT, s))
            canopyT.append((SIMD3<Float>(tp.x, 4.4 * s, tp.y), yawT, s))
        }
        scatter(trunkTemplate, trunkT, into: scene.rootNode)
        scatter(canopyTemplate, canopyT, into: scene.rootNode)

        // cones near corners
        let coneTemplate = coneNode(topRadius: 0, bottomRadius: 0.35, height: 0.9,
                                    color: UIColor(rgb: 0xf97316), segments: 8)
        var coneT: [(SIMD3<Float>, Float, Float)] = []
        for base in [60, 170, 290, 400, 520, 640, 740] {
            for c in 0..<4 {
                let idx = (base + c * 3) % Self.SAMPLES
                let n = normalOf(tangents[idx])
                let side: Float = c % 2 == 0 ? 1 : -1
                coneT.append((SIMD3<Float>(centers[idx].x + n.x * 7.3 * side, 0.45,
                                           centers[idx].y + n.y * 7.3 * side), 0, 1))
            }
        }
        scatter(coneTemplate, coneT, into: scene.rootNode)

        // distant hills
        let hillColors = [0x4d9e49, 0x55a855, 0x45923f]
        for h in 0..<9 {
            let a = Double(h) / 9 * Double.pi * 2 + Double.random(in: 0..<0.4)
            let r = 290 + Double.random(in: 0..<130)
            let hh = 26 + Double.random(in: 0..<34)
            let hill = coneNode(topRadius: 0, bottomRadius: 40 + CGFloat.random(in: 0..<45),
                                height: CGFloat(hh), color: UIColor(rgb: hillColors[h % 3]), segments: 7, casts: false)
            hill.position = SCNVector3(Float(cos(a) * r), Float(hh / 2 - 2), Float(sin(a) * r))
            hill.eulerAngles = SCNVector3(0, Float.random(in: 0..<Float.pi), 0)
            scene.rootNode.addChildNode(hill)
        }

        // drifting blocky clouds (two boxes per cloud)
        let cloudTemplate = boxNode(1, 1, 1, UIColor(rgb: 0xffffff), casts: false)
        for _ in 0..<8 {
            let x = (Float.random(in: 0..<1) - 0.5) * 480
            let y = 42 + Float.random(in: 0..<26)
            let z = (Float.random(in: 0..<1) - 0.5) * 480
            let spd = 1.2 + Float.random(in: 0..<1.6)
            let sx = 14 + Float.random(in: 0..<10)
            let c1 = cloudTemplate.flattenedClone()
            c1.scale = SCNVector3(sx, 3.5, 7)
            c1.position = SCNVector3(x, y, z)
            scene.rootNode.addChildNode(c1)
            clouds.append((c1, x, y, z, spd))
            let c2 = cloudTemplate.flattenedClone()
            c2.scale = SCNVector3(9, 3, 6)
            c2.position = SCNVector3(x + 8, y + 1.5, z + 2)
            scene.rootNode.addChildNode(c2)
            clouds.append((c2, x + 8, y + 1.5, z + 2, spd))
        }

        // lamp posts along the track (night only)
        let poleGeo = SCNCone(topRadius: 0.12, bottomRadius: 0.16, height: 5)
        poleGeo.radialSegmentCount = 6
        poleGeo.materials = [FlatMat.lit(UIColor(rgb: 0x374151))]
        let poleTemplate = SCNNode(geometry: poleGeo)
        poleTemplate.castsShadow = false
        let headTemplate = boxNode(0.9, 0.35, 0.9, UIColor(rgb: 0xffe9b0), casts: false)
        headTemplate.geometry?.materials = [FlatMat.emissive(UIColor(rgb: 0xffd77a), 1.2)]
        var lk = 0
        var li = 0
        while li < Self.SAMPLES {
            let n = normalOf(tangents[li])
            let side: Float = lk % 2 == 0 ? 1 : -1
            let lx = centers[li].x + n.x * 10.8 * side
            let lz = centers[li].y + n.y * 10.8 * side
            let pole = poleTemplate.flattenedClone()
            pole.position = SCNVector3(lx, 2.5, lz)
            lampGroup.addChildNode(pole)
            let head = headTemplate.flattenedClone()
            head.position = SCNVector3(lx, 5.1, lz)
            lampGroup.addChildNode(head)
            li += 15
            lk += 1
        }
        lampGroup.isHidden = true
        scene.rootNode.addChildNode(lampGroup)

        // rain streaks — recycled in a box around the camera (visible only when raining)
        let streakGeo = SCNBox(width: 0.03, height: 0.8, length: 0.03, chamferRadius: 0)
        let streakMat = FlatMat.unlit(UIColor(rgb: 0xaaccee))
        streakMat.transparency = 0.45
        streakGeo.materials = [streakMat]
        for _ in 0..<400 {
            let s = SCNNode(geometry: streakGeo)
            s.position = SCNVector3((Float.random(in: 0..<1) - 0.5) * 50,
                                    Float.random(in: 0..<25),
                                    (Float.random(in: 0..<1) - 0.5) * 50)
            s.castsShadow = false
            rainGroup.addChildNode(s)
            rainDrops.append(s)
        }
        rainGroup.isHidden = true
        scene.rootNode.addChildNode(rainGroup)
    }

    // MARK: - conditions

    private func applyConditions() {
        todIndex = forcedTOD ?? (game.raceCount % 3)
        raining = forcedRain ?? (Double.random(in: 0..<1) < 0.35)
        game.raceCount += 1
        game.save()
        let c = Self.tods[todIndex]

        let sky = raining ? shade(c.sky, 0.72) : UIColor(rgb: c.sky)
        scene.background.contents = sky
        scene.fogColor = sky
        scene.fogStartDistance = c.fogNear
        scene.fogEndDistance = c.fogFar

        // sky IBL for the PBR materials, scaled per time-of-day (+ rain dim)
        applySkyEnvironment(scene, intensity: (todIndex == 0 ? 1.0 : todIndex == 1 ? 0.55 : 0.15)
                                              * (raining ? 0.75 : 1))
        // bloom per TOD: subtle by day, glowing lamps/flames at night
        cameraNode.camera?.bloomIntensity = todIndex == 0 ? 0.2 : todIndex == 1 ? 0.5 : 0.9

        hemiLight.intensity = c.hemi * 1000 * (raining ? 0.85 : 1)
        hemiLight.color = UIColor(rgb: c.hemiSky)
        dirLight.intensity = c.sun * 1000
        dirLight.color = UIColor(rgb: c.sunColor)
        sunOffset = c.sunPos

        groundMat.diffuse.contents = raining ? shade(c.ground, 0.8) : UIColor(rgb: c.ground)
        groundMat.ambient.contents = groundMat.diffuse.contents
        roadMat.diffuse.contents = UIColor(rgb: raining ? 0x33373d : c.road)
        roadMat.ambient.contents = roadMat.diffuse.contents

        lampGroup.isHidden = todIndex != 2
        rainGroup.isHidden = !raining
        let text = c.name + (raining ? " · RAIN" : "")
        DispatchQueue.main.async { self.conditionsText = text }
    }

    // MARK: - run control

    private func desiredCamPos() -> SCNVector3 {
        let fx = sin(yaw), fz = cos(yaw)
        return SCNVector3(pos.x - fx * 10, 4.2, pos.y - fz * 10)
    }

    func startRun() {
        carMesh?.removeFromParentNode()
        ghost?.removeFromParentNode()
        ghost = nil
        applyConditions()
        let car = CarFactory.makeCustomCar(carState: game.car)
        scene.rootNode.addChildNode(car)
        carMesh = car
        wheels = (0..<4).compactMap { CarFactory.find(car, "tire\($0)") }
        wheelSpin = 0

        // NOS exhaust flames (flicker while boosting)
        flames = []
        let flameGeo = SCNCone(topRadius: 0, bottomRadius: 0.14, height: 0.6)
        flameGeo.radialSegmentCount = 6
        flameGeo.materials = [FlatMat.unlit(UIColor(rgb: 0xff8c1a))]
        for x in [Float(-0.5), Float(0.5)] {
            let f = SCNNode(geometry: flameGeo)
            f.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0) // point backwards
            f.position = SCNVector3(x, 0.55, -2.5)
            f.isHidden = true
            car.addChildNode(f)
            flames.append(f)
        }

        // night: headlights aimed forward
        if todIndex == 2 {
            for x in [Float(-0.6), Float(0.6)] {
                let spot = SCNLight()
                spot.type = .spot
                spot.color = UIColor(rgb: 0xfff2cc)
                spot.intensity = 1500
                spot.spotOuterAngle = 31.5  // 0.55 rad
                spot.spotInnerAngle = 16    // penumbra ~0.5
                spot.attenuationStartDistance = 2
                spot.attenuationEndDistance = 50
                let sn = SCNNode()
                sn.light = spot
                sn.position = SCNVector3(x, 0.8, 2.0)
                let tgt = SCNNode()
                tgt.position = SCNVector3(x, 0.3, 10)
                car.addChildNode(tgt)
                sn.constraints = [SCNLookAtConstraint(target: tgt)]
                car.addChildNode(sn)
            }
        }

        // state reset under the lock: the render thread may still be reading
        // these (e.g. Race Again during the finish roll)
        stateLock.lock()
        // pink-slip ghost: paces the rival's lap time along the centerline
        if let ci = challengeIndex, let rival = GameState.ladderRival(ci) {
            let g = CarFactory.makeCar(color: 0x22d3ee)
            g.opacity = 0.45
            g.position = SCNVector3(centers[0].x, 0, centers[0].y)
            g.eulerAngles = SCNVector3(0, startYaw, 0)
            scene.rootNode.addChildNode(g)
            ghost = g
            ghostTime = rival.time
        }
        stats = game.computeStats()
        maxSpd = 26 + Float(stats.speed) * 0.6
        pos = centers[0]
        yaw = startYaw
        speed = 0
        lastIdx = 0; prevIdx = 0; lastFrac = 0; passedMid = false
        offTrack = false; wasOff = false
        inputUp = false; inputDown = false; inputLeft = false; inputRight = false; inputNos = false
        nosMeter = 100
        boosting = false
        nosLockout = false
        wallCooldown = 0
        countT = 0; lastShown = 3; goT = 0
        raceT = 0; finishT = 0; finishFired = false; finishData = nil
        camPos = desiredCamPos()
        camFov = 62
        setPhaseLocked(.count)
        stateLock.unlock()
        sfx.engineSound(false) // safety: no stale loop from a previous run
        DispatchQueue.main.async {
            self.raceTimerText = "00:00.000"
            self.raceSpeedKmh = 0
            self.nosMeterInt = 100
            self.countdownText = "3"
            if let ci = self.challengeIndex, let rival = GameState.ladderRival(ci) {
                self.challengeText = "PINK SLIP: beat \(rival.name)'s \(String(format: "%.1f", rival.time))s"
            } else {
                self.challengeText = nil
            }
        }
        sfx.beep(440)
        cameraNode.position = camPos
        cameraNode.camera?.fieldOfView = camFov
    }

    /// Forfeit is only valid during countdown/racing — during the finish roll the
    /// ✕ must NOT swallow the results screen (defect fix).
    func forfeit() {
        stateLock.lock()
        guard phase == .count || phase == .racing else {
            stateLock.unlock()
            return
        }
        setPhaseLocked(.idle)
        boosting = false
        ghost?.removeFromParentNode()
        ghost = nil
        stateLock.unlock()
        sfx.nos(false)
        Haptics.nosRumble(false)
        sfx.engineSound(false)
        DispatchQueue.main.async { self.countdownText = nil }
        toasts.push("Race forfeited", .warn)
        onExit?()
    }

    func exitRace() {
        stateLock.lock()
        setPhaseLocked(.idle)
        boosting = false
        ghost?.removeFromParentNode()
        ghost = nil
        stateLock.unlock()
        sfx.nos(false)
        Haptics.nosRumble(false)
        sfx.engineSound(false)
        DispatchQueue.main.async { self.countdownText = nil }
    }

    /// Drop every held input (system touch-cancel, app backgrounding) so gas,
    /// steer and NOS can't latch with no finger down.
    func clearInputs() {
        stateLock.lock()
        inputUp = false
        inputDown = false
        inputLeft = false
        inputRight = false
        inputNos = false
        stateLock.unlock()
    }

    /// App backgrounding (defect fix): freeze handled by SceneController; here we
    /// drop inputs and silence the loops, then resume the engine cleanly on return.
    override func appActiveChanged(_ active: Bool) {
        if !active {
            clearInputs()
            stateLock.lock()
            boosting = false
            stateLock.unlock()
            sfx.nos(false)
            Haptics.nosRumble(false)
            sfx.engineSound(false)
        } else {
            stateLock.lock()
            let racing = phase == .racing
            stateLock.unlock()
            if racing { sfx.engineSound(true) }
        }
    }

    private func finishLap() {
        // Runs on the render thread under stateLock. Render-thread state is set
        // here; EVERY GameState mutation + save hops to the main thread below.
        setPhaseLocked(.finished)
        finishT = 0
        finishFired = false
        boosting = false
        ghost?.removeFromParentNode() // ghost stops at the line
        ghost = nil
        sfx.nos(false)
        Haptics.nosRumble(false)
        sfx.engineSound(false)
        for f in flames { f.isHidden = true }
        let lap = raceT
        let newBest = game.bestLap == nil || lap < game.bestLap!
        let best = newBest ? lap : game.bestLap!
        let sum = stats.speed + stats.accel + stats.handling
        let mult = max(0.5, min(1.8, 22.0 / lap))
        // pink-slip runs pay the rival's prize only — no normal reward (web parity)
        let value = challengeIndex == nil ? Int((Double(sum) * 12 * mult).rounded()) : 0
        let reward = challengeIndex == nil ? Int((Double(value) * 0.12).rounded()) : 0

        // pink-slip resolution — pure computation here; rewards applied on main
        var challengeResult: ChallengeResult? = nil
        if let ci = challengeIndex, let rival = GameState.ladderRival(ci) {
            let target = ladderWin ? 999.0 : rival.time // -ladderwin debug: auto-win
            let win = lap < target
            let becameLegend = win && ci + 1 >= 4 && !game.legend && game.ladder < 4
            challengeResult = ChallengeResult(name: rival.name, target: rival.time, win: win,
                                              margin: rival.time - lap, prizeType: rival.prizeType,
                                              prizeTier: rival.prizeTier, purse: rival.purse,
                                              becameLegend: becameLegend)
        }
        finishData = FinishData(lap: lap, best: best, value: value, reward: reward,
                                newBest: newBest, challenge: challengeResult)
        if newBest { sfx.fanfare() } else { sfx.success() } // arpeggio on a new best
        Haptics.notify(.success)

        DispatchQueue.main.async { [game, toasts] in
            if newBest { game.bestLap = lap }
            if challengeResult == nil {
                game.carValue = value
                game.cash += reward
            }
            if let ci = self.challengeIndex, let ch = challengeResult {
                if ch.win {
                    game.ladder = max(game.ladder, ci + 1)
                    game.inventory.append(game.makePart(ch.prizeType, ch.prizeTier))
                    game.cash += ch.purse
                    if game.ladder >= 4 { game.legend = true }
                    let prizeName = "\(GameState.tierNames[ch.prizeTier]) \(GameState.partLabels[ch.prizeType] ?? ch.prizeType)"
                    toasts.push("Won \(ch.name)'s \(prizeName) + $\(ch.purse)!", .good)
                } else {
                    toasts.push(String(format: "Lost to %@ by %.2fs", ch.name, lap - ch.target), .bad)
                }
            }
            game.save() // persists bestLap/reward/prize in every outcome
        }
    }

    private func nearestIndex(_ p: SIMD2<Float>, _ last: Int) -> Int {
        var best = last
        var bestD = Float.infinity
        for o in -40...40 {
            let i = (last + o + Self.SAMPLES) % Self.SAMPLES
            let dx = centers[i].x - p.x, dz = centers[i].y - p.y
            let d = dx * dx + dz * dz
            if d < bestD { bestD = d; best = i }
        }
        if bestD > 60 * 60 { // lost — full scan
            for i in 0..<Self.SAMPLES {
                let dx = centers[i].x - p.x, dz = centers[i].y - p.y
                let d = dx * dx + dz * dz
                if d < bestD { bestD = d; best = i }
            }
        }
        return best
    }

    // MARK: - frame update (render thread)

    override func update(dt: TimeInterval) {
        stateLock.lock()
        defer { stateLock.unlock() }
        // clouds drift
        for ci in clouds.indices {
            clouds[ci].x += clouds[ci].spd * Float(dt)
            if clouds[ci].x > 280 { clouds[ci].x = -280 }
            clouds[ci].node.position.x = clouds[ci].x
        }
        // rain recycle
        if !rainGroup.isHidden {
            let cx = cameraNode.position.x, cz = cameraNode.position.z
            for s in rainDrops {
                s.position.y -= 30 * Float(dt)
                if s.position.y < 0 {
                    s.position.y = 22 + Float.random(in: 0..<6)
                    s.position.x = cx + (Float.random(in: 0..<1) - 0.5) * 50
                    s.position.z = cz + (Float.random(in: 0..<1) - 0.5) * 50
                }
            }
        }

        if phase == .count {
            countT += dt
            if countT < 3 {
                let n = countT < 1 ? 3 : countT < 2 ? 2 : 1
                if n != lastShown {
                    lastShown = n
                    DispatchQueue.main.async { self.countdownText = "\(n)" }
                    sfx.beep(440)
                }
            } else {
                // render-thread-owned transition → fires exactly once
                setPhaseLocked(.racing)
                raceT = 0
                goT = 0.9
                DispatchQueue.main.async { self.countdownText = "GO!" }
                sfx.beep(880)
                sfx.engineSound(true) // engine loop starts on GO
            }
        }

        if phase == .racing {
            raceT += dt
            // debug -instantfinish: force the lap done ~1s after GO (deterministic
            // tests). finishData != nil guards the same-frame window before the
            // phase flip takes effect next frame.
            if instantFinish && raceT > 1 && finishData == nil {
                finishLap()
            }
            if goT > 0 {
                goT -= dt
                if goT <= 0 {
                    DispatchQueue.main.async { self.countdownText = nil }
                }
            }

            // debug auto-drive: steer toward a lookahead point on the centerline, hold gas
            if autoDrive {
                let ahead = centers[(lastIdx + 12) % Self.SAMPLES]
                let wantYaw = atan2(ahead.x - pos.x, ahead.y - pos.y)
                var err = wantYaw - yaw
                while err > Float.pi { err -= 2 * Float.pi }
                while err < -Float.pi { err += 2 * Float.pi }
                inputLeft = err > 0.06
                inputRight = err < -0.06
                inputUp = abs(err) < 0.9
                inputDown = false
                inputNos = false
            }

            // NOS boost: drains while held + moving, regens otherwise, dies at 0.
            // Lockout: once the meter hits 0 while held, boosting cannot restart
            // until the input is released AND the meter refilled past 15 —
            // flames/SFX die once on empty instead of strobing at 0.
            let wantBoost = inputNos && !nosLockout
            let canBoost = nosMeter > 0 && abs(speed) > 0.5
            let nowBoosting = wantBoost && canBoost
            if nowBoosting && !boosting { sfx.nos(true); Haptics.nosRumble(true) }
            if !nowBoosting && boosting { sfx.nos(false); Haptics.nosRumble(false) }
            boosting = nowBoosting
            if boosting { nosMeter = max(0, nosMeter - 30 * Float(dt)) }
            else { nosMeter = min(100, nosMeter + 8 * Float(dt)) }
            if boosting { Haptics.nosRumbleLevel(nosMeter / 100) } // rumble tracks the tank
            if inputNos && nosMeter <= 0 { nosLockout = true }
            if nosLockout && !inputNos && nosMeter > 15 { nosLockout = false }
            sfx.setEngineRPM(Double(abs(speed) / maxSpd))
            for f in flames {
                f.isHidden = !boosting
                if boosting {
                    f.scale = SCNVector3(0.8 + Float.random(in: 0..<0.5),
                                         0.6 + Float.random(in: 0..<0.9),
                                         0.8 + Float.random(in: 0..<0.5))
                }
            }

            let accelRate = (10 + Float(stats.accel) * 0.28) * (boosting ? 1.5 : 1)
            let effMax = (offTrack ? maxSpd * 0.45 : maxSpd) * (boosting ? 1.35 : 1)
            let brakeDecel: Float = 30 * (raining ? 0.85 : 1)
            let grip: Float = raining ? 0.8 : 1

            if inputUp { speed += accelRate * Float(dt) }
            if inputDown {
                if speed > 0.5 { speed -= brakeDecel * Float(dt) }   // brake
                else { speed -= accelRate * 0.6 * Float(dt) }        // reverse
            }
            if !inputUp && !inputDown { speed -= speed * 0.6 * Float(dt) } // natural drag
            if offTrack { speed -= speed * 2.0 * Float(dt) }               // heavy off-track drag
            speed = max(-12, min(effMax, speed))
            if !inputUp && !inputDown && abs(speed) < 0.05 { speed = 0 }

            // steering (no turning at standstill; steering bleeds a little speed)
            let steer: Float = (inputLeft ? 1 : 0) - (inputRight ? 1 : 0)
            let turnRate = (1.4 + Float(stats.handling) * 0.022) * grip
            let steerScale = min(1, abs(speed) / 12)
            if steer != 0 && steerScale > 0 {
                yaw += steer * turnRate * steerScale * Float(dt) * (speed < 0 ? -1 : 1)
                speed -= speed * 0.18 * steerScale * Float(dt)
            }

            // move
            let fx = sin(yaw), fz = cos(yaw)
            pos.x += fx * speed * Float(dt)
            pos.y += fz * speed * Float(dt)

            // nearest centerline sample (sliding window, full scan fallback)
            lastIdx = nearestIndex(pos, lastIdx)
            let c = centers[lastIdx]
            let t = tangents[lastIdx]
            let nx = -t.y, nz = t.x
            var lat = (pos.x - c.x) * nx + (pos.y - c.y) * nz

            // soft barrier wall: the position clamp applies every frame, but the
            // speed penalty fires at most once per 0.25s (frame-rate independent)
            wallCooldown = max(0, wallCooldown - dt)
            if abs(lat) > Self.BARRIER_LAT {
                let s: Float = lat > 0 ? 1 : -1
                pos.x = c.x + nx * Self.BARRIER_LAT * s
                pos.y = c.y + nz * Self.BARRIER_LAT * s
                lat = Self.BARRIER_LAT * s
                if wallCooldown <= 0 {
                    Haptics.barrierThud(min(1, abs(speed) / maxSpd)) // thud scaled by impact
                    speed *= 0.5
                    wallCooldown = 0.25
                }
            }

            offTrack = abs(lat) > Self.ROAD_HALF
            if offTrack && !wasOff { toasts.push("Off track!", .warn) }
            wasOff = offTrack

            // lap detection: wrap from >90% to <10% of samples, mid checkpoint
            // required — and the checkpoint only arms via FORWARD travel
            // (index increasing), so wrong-way drivers can't validate a lap
            let idxDelta = (lastIdx - prevIdx + Self.SAMPLES) % Self.SAMPLES
            let movingForward = idxDelta > 0 && idxDelta < Self.SAMPLES / 2
            prevIdx = lastIdx
            let frac = Double(lastIdx) / Double(Self.SAMPLES)
            if frac > 0.45 && frac < 0.55 && movingForward { passedMid = true }
            if lastFrac > 0.9 && frac < 0.1 && passedMid && raceT > 5 { finishLap() }
            lastFrac = frac

            // rival ghost paces the target time (pink-slip only, no collision)
            if let ghost, ghostTime > 0 {
                let f = min(1.5, raceT / ghostTime) * Double(Self.SAMPLES)
                let i0 = Int(f) % Self.SAMPLES
                let i1 = (i0 + 1) % Self.SAMPLES
                let fr = Float(f - floor(f))
                let gp = centers[i0] + (centers[i1] - centers[i0]) * fr
                ghost.position = SCNVector3(gp.x, 0, gp.y)
                let gt = tangents[i0]
                ghost.eulerAngles = SCNVector3(0, atan2(gt.x, gt.y), 0)
            }

            carMesh?.position = SCNVector3(pos.x, 0, pos.y)
            carMesh?.eulerAngles = SCNVector3(0, yaw, 0)

            // wheels: spin by speed/radius; the front two steer with the input
            wheelSpin += speed / CarFactory.wheelRadius * Float(dt)
            for (i, w) in wheels.enumerated() {
                w.eulerAngles = SCNVector3(wheelSpin, i < 2 ? steer * 0.4 : 0, 0)
            }
        }

        if phase == .finished, let car = carMesh {
            // roll to a stop, then hand results to main
            speed -= speed * 1.8 * Float(dt)
            let fx = sin(yaw), fz = cos(yaw)
            pos.x += fx * speed * Float(dt)
            pos.y += fz * speed * Float(dt)
            car.position = SCNVector3(pos.x, 0, pos.y)
            car.eulerAngles = SCNVector3(0, yaw, 0)
            wheelSpin += speed / CarFactory.wheelRadius * Float(dt)
            for w in wheels { w.eulerAngles.x = wheelSpin }
            finishT += dt
            if finishT > 1.3 && !finishFired {
                finishFired = true
                if let data = finishData {
                    DispatchQueue.main.async { self.onFinish?(data) }
                }
            }
        }

        // chase camera
        if carMesh != nil {
            let k = 1 - exp(-6 * dt)
            let target = desiredCamPos()
            camPos.x += (target.x - camPos.x) * Float(k)
            camPos.y += (target.y - camPos.y) * Float(k)
            camPos.z += (target.z - camPos.z) * Float(k)
            cameraNode.position = camPos
            if offTrack && phase == .racing {
                cameraNode.position.x += Float((Double.random(in: 0..<1) - 0.5) * 0.16)
                cameraNode.position.y += Float((Double.random(in: 0..<1) - 0.5) * 0.1)
                cameraNode.position.z += Float((Double.random(in: 0..<1) - 0.5) * 0.16)
            }
            let fx = sin(yaw), fz = cos(yaw)
            cameraNode.look(at: SCNVector3(pos.x + fx * 6, 1.5, pos.y + fz * 6))
            let targetFov = 62 + 16 * min(1, CGFloat(abs(speed)) / CGFloat(maxSpd)) + (boosting ? 8 : 0)
            camFov += (targetFov - camFov) * CGFloat(1 - exp(-4 * dt))
            cameraNode.camera?.fieldOfView = camFov
            // shadow light follows the car
            dirLightNode.position = SCNVector3(pos.x + sunOffset.x, sunOffset.y, pos.y + sunOffset.z)
            sunTarget.position = SCNVector3(pos.x, 0, pos.y)
        }

        // throttled HUD publish (30 Hz, main thread)
        publishT += dt
        if publishT >= 1.0 / 30 {
            publishT = 0
            let timerText = Self.fmtTime(raceT)
            let kmh = Int((abs(speed) * 3.4).rounded()) // round, not truncate
            let nos = Int(nosMeter.rounded())
            let playerDot = mapPoint(pos)
            DispatchQueue.main.async {
                self.raceTimerText = timerText
                self.raceSpeedKmh = kmh
                self.nosMeterInt = nos
                self.minimapPlayer = playerDot
            }
        }
    }

    static func fmtTime(_ t: Double?) -> String {
        guard let t, t.isFinite else { return "—" }
        let m = Int(t / 60)
        let s = Int(t.truncatingRemainder(dividingBy: 60))
        let ms = Int((t * 1000).truncatingRemainder(dividingBy: 1000))
        return String(format: "%02d:%02d.%03d", m, s, ms)
    }
}
