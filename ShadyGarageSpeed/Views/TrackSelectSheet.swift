// TrackSelectSheet.swift — pre-race track picker (web #1): TRACKS rows with
// feel, par, and per-track best lap.
import SwiftUI

struct TrackSelectSheet: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss
    private static let todNames = ["Day", "Sunset", "Night"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🏁 Pick a track")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "track-close") { dismiss() }
            }

            // #7 daily challenge card (deterministic per date)
            let dc = GameState.dailyChallenge()
            let doneToday = app.game.dailyChallengeDate == todayKey()
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("📅 Daily Run\(doneToday ? " ✓" : "")")
                        .font(sgsFont(15, .bold))
                    Text("\(GameState.tracks[dc.trackIndex].name)\(dc.reversed ? " ⇄" : "") · \(Self.todNames[dc.tod]) · \(dc.wx.uppercased())")
                        .font(sgsFont(12))
                        .foregroundStyle(Color.sgsMuted)
                    Text(doneToday ? "bonus claimed today" : "+$200 · +$100 under \(String(format: "%.1f", dc.par * 1.05))s")
                        .font(sgsFont(12, .semibold))
                        .foregroundStyle(Color.sgsCyan)
                }
                Spacer()
                SGSButton(title: "Race", small: true, a11y: "daily-run",
                          hint: "Race today's seeded challenge") {
                    dismiss()
                    app.startDailyRun()
                }
            }
            .padding(10)
            .background(Color.sgsAccent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sgsAccent.opacity(0.35), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("daily-card")

            ForEach(GameState.tracks.indices, id: \.self) { i in
                let t = GameState.tracks[i]
                let rev = app.trackReversed.contains(t.id) // #20 direction flip
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name + (rev ? " ⇄" : ""))
                            .font(sgsFont(15, .bold))
                        Text("\(t.feel.capitalized) · Par \(String(format: "%.0f", t.par + (rev ? 1 : 0)))\(rev ? " · reversed" : "")")
                            .font(sgsFont(12))
                            .foregroundStyle(Color.sgsMuted)
                        Text("Best: \(RaceScene.fmtTime(game.bestLaps[t.id + (rev ? "R" : "")]))")
                            .font(sgsFont(12, .semibold))
                            .foregroundStyle(Color.sgsCyan)
                    }
                    Spacer()
                    SGSButton(title: "⇄", ghost: !rev, small: true, a11y: "track-flip-\(i)",
                              label: "Flip direction",
                              hint: rev ? "Drive \(t.name) forwards" : "Drive \(t.name) backwards") {
                        // #20 session-only flip; par +1s and bests keyed per direction
                        if rev { app.trackReversed.remove(t.id) } else { app.trackReversed.insert(t.id) }
                    }
                    SGSButton(title: "Race", small: true, a11y: "track-row-\(i)",
                              hint: "Start a time trial on \(t.name)") {
                        dismiss()
                        app.startRaceOnTrack(i)
                    }
                }
                .padding(10)
                .background(Color.sgsCard2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .contain)
            }
            Spacer()
        }
        .padding(20)
        .foregroundStyle(Color.sgsText)
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
    }
}
