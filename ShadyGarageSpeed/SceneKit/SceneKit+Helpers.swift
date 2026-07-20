// SceneKit+Helpers.swift — shared SCN helpers: colors, materials, primitive nodes,
// and the SceneController base class.
import SceneKit
import ModelIO
import UIKit

// MARK: - Colors

extension UIColor {
    convenience init(rgb: Int, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// Multiply a hex color's RGB by f (matches THREE.Color.multiplyScalar).
func shade(_ hex: Int, _ f: CGFloat) -> UIColor {
    UIColor(red: min(1, CGFloat((hex >> 16) & 0xFF) / 255 * f),
            green: min(1, CGFloat((hex >> 8) & 0xFF) / 255 * f),
            blue: min(1, CGFloat(hex & 0xFF) / 255 * f),
            alpha: 1)
}

// MARK: - Materials

enum FlatMat {
    /// Lit matte material (MeshStandardMaterial analogue). PBR so the assigned
    /// roughness/metalness actually take effect (they are silently ignored under
    /// .lambert). ambient.contents mirrors diffuse so SCN ambient lights still
    /// act like three.js hemisphere fill alongside the sky IBL.
    static func lit(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.ambient.contents = color
        m.roughness.contents = 0.8
        m.metalness.contents = 0.05
        return m
    }
    /// Unlit material (MeshBasicMaterial analogue).
    static func unlit(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        return m
    }
    /// Lit material with emission (for headlights, lamps, neon).
    static func emissive(_ color: UIColor, _ intensity: CGFloat = 0.5) -> SCNMaterial {
        let m = lit(color)
        m.emission.contents = color
        m.emission.intensity = intensity
        return m
    }
}

/// Procedural sky IBL (zero assets) so PBR materials get believable ambient and
/// specular response; per-scene intensity keeps the look aligned with the old
/// lambert render rather than redesigning it.
func applySkyEnvironment(_ scene: SCNScene, intensity: CGFloat) {
    let sky = MDLSkyCubeTexture()
    sky.turbidity = 0.55
    sky.upperAtmosphereScattering = 0.4
    sky.groundAlbedo = 0.35
    scene.lightingEnvironment.contents = sky
    scene.lightingEnvironment.intensity = intensity
}

// MARK: - Primitive nodes (mirror web box()/mesh helpers)

func boxNode(_ w: CGFloat, _ h: CGFloat, _ d: CGFloat, _ color: UIColor,
             _ x: CGFloat = 0, _ y: CGFloat = 0, _ z: CGFloat = 0,
             name: String? = nil, unlit: Bool = false, casts: Bool = true) -> SCNNode {
    let geo = SCNBox(width: w, height: h, length: d, chamferRadius: 0)
    geo.materials = [unlit ? FlatMat.unlit(color) : FlatMat.lit(color)]
    let n = SCNNode(geometry: geo)
    n.position = SCNVector3(Float(x), Float(y), Float(z))
    n.castsShadow = casts
    n.name = name
    return n
}

func cylNode(radius: CGFloat, height: CGFloat, color: UIColor, segments: Int = 12,
             name: String? = nil, unlit: Bool = false, casts: Bool = true) -> SCNNode {
    let geo = SCNCylinder(radius: radius, height: height)
    geo.radialSegmentCount = segments
    geo.materials = [unlit ? FlatMat.unlit(color) : FlatMat.lit(color)]
    let n = SCNNode(geometry: geo)
    n.castsShadow = casts
    n.name = name
    return n
}

func coneNode(topRadius: CGFloat, bottomRadius: CGFloat, height: CGFloat,
              color: UIColor, segments: Int = 12, name: String? = nil,
              unlit: Bool = false, casts: Bool = true) -> SCNNode {
    let geo = SCNCone(topRadius: topRadius, bottomRadius: bottomRadius, height: height)
    geo.radialSegmentCount = segments
    geo.materials = [unlit ? FlatMat.unlit(color) : FlatMat.lit(color)]
    let n = SCNNode(geometry: geo)
    n.castsShadow = casts
    n.name = name
    return n
}

func sphereNode(radius: CGFloat, color: UIColor, segments: Int = 8,
                name: String? = nil, unlit: Bool = false) -> SCNNode {
    let geo = SCNSphere(radius: radius)
    geo.segmentCount = segments
    geo.materials = [unlit ? FlatMat.unlit(color) : FlatMat.lit(color)]
    let n = SCNNode(geometry: geo)
    n.castsShadow = true
    n.name = name
    return n
}

// MARK: - SceneController base

/// Owns the SCNScene + camera, ticks update(dt:) from the render loop with a 0.05s clamp.
/// When `appActive` is false (backgrounded/inactive) the sim freezes outright —
/// no integration, no dt spike on resume.
class SceneController: NSObject, ObservableObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private var lastTime: TimeInterval = 0

    /// Set by AppState from scenePhase. Subclasses override appActiveChanged for
    /// audio/input cleanup.
    var appActive = true {
        didSet {
            if appActive == oldValue { return }
            if !appActive { lastTime = 0 } // resume without a dt spike
            appActiveChanged(appActive)
        }
    }

    override init() {
        super.init()
        let cam = SCNCamera()
        cam.zNear = 0.1
        cam.zFar = 600
        cameraNode.camera = cam
        scene.rootNode.addChildNode(cameraNode)
    }

    func resetClock() { lastTime = 0 }

    /// Called on appActive transitions (main thread). Base implementation does nothing.
    func appActiveChanged(_ active: Bool) {}

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard appActive else { lastTime = time; return }
        let dt = lastTime == 0 ? 0 : min(0.05, time - lastTime)
        lastTime = time
        update(dt: dt)
    }

    /// Subclasses override. Runs on the SceneKit render thread — keep UI publishes on main.
    func update(dt: TimeInterval) {}
}
