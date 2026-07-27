// LugnutShared.swift — #55 Daily Lugnut widget data bridge.
// The app writes the latest headline here on every publish; the widget extension
// reads it through the App Group container (group.com.noshu.shadygaragespeed —
// see both entitlements files; the simulator works unsigned, device needs the
// App Groups capability on both targets).
import Foundation

enum LugnutShared {
    static let suiteName = "group.com.noshu.shadygaragespeed"
    private static let headlineKey = "lugnut_headline"
    private static let dayKey = "lugnut_day"

    static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    /// App-side: called on every Daily Lugnut publish.
    static func publish(headline: String, day: Int) {
        defaults?.set(headline, forKey: headlineKey)
        defaults?.set(day, forKey: dayKey)
    }

    /// Widget-side: the most recent headline, if any.
    static func latest() -> (headline: String, day: Int)? {
        guard let d = defaults, let h = d.string(forKey: headlineKey) else { return nil }
        return (h, d.integer(forKey: dayKey))
    }
}
