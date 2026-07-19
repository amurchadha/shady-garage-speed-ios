// Haptics.swift — light haptic feedback for key game events (steal, cops, race finish).
import UIKit

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
}
