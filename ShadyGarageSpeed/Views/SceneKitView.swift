// SceneKitView.swift — UIViewRepresentable wrapper around SCNView for a SceneController.
import SceneKit
import SwiftUI

struct SceneKitView: UIViewRepresentable {
    let controller: SceneController
    var onTap: ((CGPoint, SCNView) -> Void)? = nil

    final class Coordinator: NSObject {
        var onTap: ((CGPoint, SCNView) -> Void)?
        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let view = gr.view as? SCNView else { return }
            onTap?(gr.location(in: view), view)
        }
    }

    func makeCoordinator() -> Coordinator {
        let c = Coordinator()
        c.onTap = onTap
        return c
    }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = controller.scene
        v.delegate = controller
        v.pointOfView = controller.cameraNode
        v.isPlaying = true
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.allowsCameraControl = false
        if onTap != nil {
            let tap = UITapGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handleTap(_:)))
            v.addGestureRecognizer(tap)
        }
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onTap = onTap
    }
}
