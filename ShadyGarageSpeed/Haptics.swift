// Haptics.swift — haptic feedback: UIKit notification generators for one-shot
// events (steal, cops, race finish), CoreHaptics for choreography (NOS rumble,
// barrier thuds, minigame ticks). All CoreHaptics paths are capability-guarded
// and fail silent (no haptics on the simulator).
import UIKit
import CoreHaptics

enum Haptics {
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(type)
        }
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        DispatchQueue.main.async {
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        }
    }

    // MARK: - CoreHaptics choreography

    /// Lazy CHHapticEngine owner. Every call is a no-op on unsupported hardware.
    private enum Engine {
        static let shared = EngineImpl()
    }

    private final class EngineImpl {
        let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        private var engine: CHHapticEngine?
        private var rumble: CHHapticPatternPlayer?

        init() {
            guard supported else { return }
            engine = try? CHHapticEngine()
            engine?.isAutoShutdownEnabled = true
            engine?.resetHandler = { [weak self] in
                try? self?.engine?.start()
                self?.rumble = nil
            }
            engine?.stoppedHandler = { _ in }
            try? engine?.start()
        }

        /// One-shot transient. intensity/sharpness 0…1.
        func transient(_ intensity: Float, _ sharpness: Float) {
            guard supported, let engine else { return }
            do {
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: max(0, min(1, intensity))),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: max(0, min(1, sharpness))),
                ], relativeTime: 0)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
            } catch { /* fail silent */ }
        }

        /// Continuous rumble used by NOS; call setRumble(0)/stopRumble to cut.
        func startRumble() {
            guard supported, let engine, rumble == nil else { return }
            do {
                let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35),
                ], relativeTime: 0, duration: 3600)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makeAdvancedPlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                rumble = player
            } catch { /* fail silent */ }
        }

        func setRumble(intensity: Float) {
            guard let player = rumble as? CHHapticAdvancedPatternPlayer else { return }
            let clamped = max(0, min(1, intensity))
            try? player.sendParameters([
                CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: clamped, relativeTime: 0),
            ], atTime: CHHapticTimeImmediate)
        }

        func stopRumble() {
            guard let player = rumble else { return }
            rumble = nil
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
    }

    // MARK: game events

    /// NOS boost: continuous rumble whose intensity tracks the remaining tank.
    static func nosRumble(_ on: Bool) {
        if on { Engine.shared.startRumble() } else { Engine.shared.stopRumble() }
    }

    /// Live tank level while boosting (0…1).
    static func nosRumbleLevel(_ frac: Float) {
        Engine.shared.setRumble(intensity: 0.25 + 0.75 * frac)
    }

    /// Barrier soft-wall hit: transient thud scaled by impact speed (0…1).
    static func barrierThud(_ intensity: Float) {
        Engine.shared.transient(0.4 + 0.6 * max(0, min(1, intensity)), 0.15)
    }

    /// Minigame marker crossing a zone edge: subtle tick.
    static func zoneTick() {
        Engine.shared.transient(0.3, 0.8)
    }
}
