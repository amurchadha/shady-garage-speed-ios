// LiveActivityManager.swift — #57 Live Activity race timer (app side).
// Started at GO, updated ~1Hz with the running lap time + speed, ended on
// finish/forfeit/exit. The UI is rendered by the widget extension
// (ShadyGarageSpeedWidget/RaceLiveActivity.swift) — the system only runs
// extension code on the lock screen, so the extension must be installed for the
// activity to be visible. Fully local (pushType: nil): no server, no paid-account
// push capability needed; only NSSupportsLiveActivities in Info.plist.
// ActivityKit is unavailable on Mac Catalyst (#60) — no-op stubs there.
#if !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

enum LiveActivityManager {
    private static var activity: Activity<RaceActivityAttributes>?

    static func start(trackName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attrs = RaceActivityAttributes(trackName: trackName)
        let state = RaceActivityAttributes.ContentState(raceT: 0, speedKmh: 0)
        activity = try? Activity.request(
            attributes: attrs,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil)
    }

    /// Called ~1Hz while racing (update budget is limited — no per-frame spam).
    static func update(raceT: Double, speedKmh: Int) {
        guard let activity else { return }
        let state = RaceActivityAttributes.ContentState(raceT: raceT, speedKmh: speedKmh)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// finalLap: the finished lap time (shows briefly before dismissing), nil on
    /// forfeit/exit (dismiss immediately).
    static func end(finalLap: Double?) {
        guard let activity else { return }
        Self.activity = nil
        let state = RaceActivityAttributes.ContentState(raceT: finalLap ?? 0, speedKmh: 0)
        let policy: ActivityUIDismissalPolicy = finalLap != nil ? .after(.now + 4) : .immediate
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: policy) }
    }
}

#else

enum LiveActivityManager {
    static func start(trackName: String) {}
    static func update(raceT: Double, speedKmh: Int) {}
    static func end(finalLap: Double?) {}
}

#endif
