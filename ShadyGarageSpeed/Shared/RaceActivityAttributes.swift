// RaceActivityAttributes.swift — #57 Live Activity content contract.
// Compiled into BOTH the app (starts/updates/ends the activity) and the widget
// extension (renders it — the system only runs extension code on the lock screen).
// ActivityKit is unavailable on Mac Catalyst (#60) — the type compiles away there.
#if !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

struct RaceActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var raceT: Double   // running lap time, seconds
        var speedKmh: Int
    }
    var trackName: String

    /// mm:ss.mmm — shared by the lock-screen banner and Dynamic Island.
    static func fmtTime(_ t: Double) -> String {
        let m = Int(t) / 60, s = Int(t) % 60, ms = Int((t * 1000).truncatingRemainder(dividingBy: 1000))
        return String(format: "%02d:%02d.%03d", m, s, ms)
    }
}
#endif
