// AppIntents.swift — #58 Siri/Shortcuts integration:
// "Start a race in Shady Garage & Speed" (opens the app on the track picker) and
// "What's my best lap?" (reads the save, returns a spoken answer). iOS 16+,
// no entitlements required; intents run in the app process.
import AppIntents
import Foundation

struct StartRaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a race in Shady Garage & Speed"
    static var description = IntentDescription("Opens the app on the track picker, ready to race.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        DeepLinkCenter.post("track-select")
        return .result()
    }
}

struct BestLapIntent: AppIntent {
    static var title: LocalizedStringResource = "What's my best lap?"
    static var description = IntentDescription("Reads your best lap per track from the save.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Decode the save blob read-only — no AppState needed in the intent process.
        guard let json = UserDefaults.standard.data(forKey: "sgs_save"),
              let raw = try? JSONDecoder().decode(RawSave.self, from: json) else {
            return .result(dialog: "No laps on record yet — hit the track first.")
        }
        var laps = raw.bestLaps ?? [:]
        if laps["classic"] == nil, let legacy = raw.bestLap { laps["classic"] = legacy }
        guard !laps.isEmpty else {
            return .result(dialog: "No laps on record yet — hit the track first.")
        }
        var parts: [String] = []
        if let t = laps["classic"] { parts.append("Meadow Loop \(RaceScene.fmtTime(t))") }
        if let t = laps["ridge"] { parts.append("Figure-8 Ridge \(RaceScene.fmtTime(t))") }
        return .result(dialog: "Your best laps: \(parts.joined(separator: ", ")).")
    }
}

struct SGSShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRaceIntent(),
                    phrases: ["Start a race in \(.applicationName)",
                              "Race in \(.applicationName)"],
                    shortTitle: "Start a Race",
                    systemImageName: "flag.checkered")
        AppShortcut(intent: BestLapIntent(),
                    phrases: ["What's my best lap in \(.applicationName)",
                              "Best lap in \(.applicationName)"],
                    shortTitle: "Best Lap",
                    systemImageName: "timer")
    }
}
