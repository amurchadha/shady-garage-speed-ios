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
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.name)
                            .font(.system(size: 15, weight: .bold))
                        Text(f.desc)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.sgsMuted)
                    }
                    Spacer()
                    if hired {
                        Text("HIRED ✓")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(Color.sgsGood)
                    } else {
                        SGSButton(title: "Hire $\(price)", small: true,
                                  disabled: game.cash < price, a11y: "hire-\(i)") {
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
