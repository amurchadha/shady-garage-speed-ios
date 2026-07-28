// TrackSelectSheet.swift — pre-race track picker (web #1): TRACKS rows with
// feel, par, and per-track best lap.
import SwiftUI

struct TrackSelectSheet: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🏁 Pick a track")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "track-close") { dismiss() }
            }

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
