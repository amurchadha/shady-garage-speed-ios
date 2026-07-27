// RaceLiveActivity.swift — #57 Live Activity race timer (extension side: the
// system renders ONLY extension code on the lock screen / Dynamic Island).
// The app drives it via LiveActivityManager (start at GO, 1Hz updates, end at
// finish/forfeit/exit). No push — fully local, so no paid-account requirement
// beyond the app's own signing.
import ActivityKit
import WidgetKit
import SwiftUI

struct RaceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RaceActivityAttributes.self) { context in
            // Lock-screen banner: track · running timer · speed
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.trackName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(RaceActivityAttributes.fmtTime(context.state.raceT))
                        .font(.title3.monospacedDigit().bold())
                }
                Spacer()
                Text("\(context.state.speedKmh) km/h")
                    .font(.headline.monospacedDigit())
            }
            .padding(12)
            .activityBackgroundTint(.black.opacity(0.75))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack {
                        Text(RaceActivityAttributes.fmtTime(context.state.raceT))
                            .font(.title2.monospacedDigit().bold())
                        Spacer()
                        Text("\(context.state.speedKmh) km/h")
                            .font(.headline.monospacedDigit())
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.trackName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "flag.checkered")
            } compactTrailing: {
                Text(RaceActivityAttributes.fmtTime(context.state.raceT))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "flag.checkered")
            }
        }
    }
}
