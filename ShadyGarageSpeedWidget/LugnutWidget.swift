// LugnutWidget.swift — #55 Daily Lugnut home-screen widget (small).
// Shows the latest tabloid headline the app published to the App Group store;
// timeline refreshes at midnight (a new headline also lands on the next app save).
import WidgetKit
import SwiftUI

private struct LugnutEntry: TimelineEntry {
    let date: Date
    let headline: String
    let day: Int
}

private struct LugnutProvider: TimelineProvider {
    private static let fallback = "LOCAL GARAGE DEFINITELY NOT UNDER INVESTIGATION"

    func placeholder(in context: Context) -> LugnutEntry {
        LugnutEntry(date: Date(), headline: Self.fallback, day: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (LugnutEntry) -> Void) {
        let latest = LugnutShared.latest()
        completion(LugnutEntry(date: Date(),
                               headline: latest?.headline ?? Self.fallback,
                               day: latest?.day ?? 0))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LugnutEntry>) -> Void) {
        let latest = LugnutShared.latest()
        let entry = LugnutEntry(date: Date(),
                                headline: latest?.headline ?? Self.fallback,
                                day: latest?.day ?? 0)
        // daily tabloid: refresh at midnight
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86400)
        completion(Timeline(entries: [entry], policy: .after(midnight)))
    }
}

struct LugnutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.noshu.shadygaragespeed.lugnut",
                            provider: LugnutProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Text("THE DAILY LUGNUT")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(entry.headline)
                    .font(.caption.bold())
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if entry.day > 0 {
                    Text("Day \(entry.day)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .containerBackground(Color(red: 0.93, green: 0.90, blue: 0.80), for: .widget) // newsprint
        }
        .configurationDisplayName("The Daily Lugnut")
        .description("Today's headline from your garage's favorite tabloid.")
        .supportedFamilies([.systemSmall])
    }
}
