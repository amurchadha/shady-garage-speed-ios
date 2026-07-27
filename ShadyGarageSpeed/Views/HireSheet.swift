// HireSheet.swift — crew hire (Feature: hire the unchosen friends for their perks).
import SwiftUI

struct HireSheet: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("👥 Hire the Crew")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "crew-close") { dismiss() }
            }

            ForEach(GameState.friends.indices.filter { $0 != game.characterIndex }, id: \.self) { i in
                let f = GameState.friends[i]
                let hired = game.crew.contains(i)
                let price = GameState.crewPrices[i]
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color(rgb: f.color))
                            .frame(width: 34, height: 34)
                        Text(String(f.name.prefix(1)))
                            .font(sgsFont(16, .black))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name)
                            .font(sgsFont(15, .bold))
                        Text(f.desc)
                            .font(sgsFont(12))
                            .foregroundStyle(Color.sgsMuted)
                    }
                    Spacer()
                    if hired {
                        Text("HIRED ✓")
                            .font(sgsFont(12, .black))
                            .foregroundStyle(Color.sgsGood)
                    } else {
                        SGSButton(title: "Hire $\(price)", small: true,
                                  disabled: game.cash < price, a11y: "hire-\(i)",
                                  label: "Hire \(f.name) for $\(price)",
                                  hint: f.desc) {
                            if game.hireCrew(i) {
                                app.toasts.push("\(f.name) joined the crew! \(f.desc)", .good)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color.sgsCard2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
        }
        .padding(20)
        .foregroundStyle(Color.sgsText)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}
