// LadderSheet.swift — pink-slip rival ladder (Feature A): beaten ✓ / current 🏁
// (target + prize + Challenge) / locked 🔒 rows, Street Legend state.
import SwiftUI

struct LadderSheet: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🏆 Rival Ladder")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "ladder-close") { dismiss() }
            }

            if game.legend {
                Text("👑 You are the Street Legend")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color(rgb: 0xf59e0b))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .accessibilityIdentifier("ladder-legend")
            }

            VStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { pos in
                    row(pos)
                }
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.sgsCard.ignoresSafeArea())
        .foregroundStyle(Color.sgsText)
    }

    @ViewBuilder
    private func row(_ pos: Int) -> some View {
        let rival = GameState.ladderRival(pos)!
        let beaten = pos < game.ladder
        let current = pos == game.ladder && !game.legend
        let prize = "\(GameState.tierNames[rival.prizeTier]) \(GameState.partLabels[rival.prizeType] ?? rival.prizeType) + $\(rival.purse)"
        HStack(spacing: 10) {
            Text(beaten ? "✓" : current ? "🏁" : "🔒")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(beaten ? Color.sgsGood : Color.sgsText)
                .frame(width: 24)
                .accessibilityIdentifier("ladder-row-\(pos)")
            VStack(alignment: .leading, spacing: 2) {
                Text(rival.name)
                    .font(.system(size: 15, weight: .bold))
                Text("Target \(String(format: "%.1f", rival.time))s · \(prize)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.sgsMuted)
            }
            Spacer()
            if current {
                SGSButton(title: "Challenge", small: true, a11y: "ladder-challenge") {
                    dismiss()
                    app.startChallenge(pos)
                }
            }
        }
        .padding(10)
        .background(Color.sgsCard2.opacity(current ? 1 : 0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(!beaten && !current ? 0.6 : 1)
    }
}
