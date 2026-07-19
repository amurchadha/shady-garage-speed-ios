// ResultsView.swift — lap results + rival leaderboard (mirrors #screen-results).
import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ZStack {
            SceneKitView(controller: app.raceScene)
                .ignoresSafeArea()
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            if let res = app.lastFinish {
                ScrollView {
                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Text("🏁 Lap Complete!")
                                .font(.title2.bold())
                            if res.newBest {
                                Text("NEW BEST!")
                                    .font(.system(size: 12, weight: .black))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 3)
                                    .background(Color(rgb: 0xf59e0b))
                                    .foregroundStyle(Color(rgb: 0x0b0e14))
                                    .clipShape(Capsule())
                            }
                        }

                        VStack(spacing: 6) {
                            resRow("Lap time", RaceScene.fmtTime(res.lap), Color.sgsText)
                            resRow("Best lap", RaceScene.fmtTime(res.best), Color.sgsText)
                            resRow("Car value", "$\(res.value)", Color(rgb: 0xf59e0b))
                            resRow("Prize", "+$\(res.reward)", Color.sgsGood)
                        }

                        leaderboard(lap: res.lap)

                        HStack {
                            SGSButton(title: "Race Again") { app.raceAgain() }
                            Spacer()
                            SGSButton(title: "Back to Garage", ghost: true) { app.backToGarage() }
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                    .frame(maxWidth: 540)
                    .background(Color.sgsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundStyle(Color.sgsText)
    }

    private func resRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color.sgsMuted)
            Spacer()
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func leaderboard(lap: Double) -> some View {
        var rows = GameState.rivals.map { (name: $0.name, time: $0.time, you: false) }
        rows.append((name: "YOU", time: lap, you: true))
        rows.sort { $0.time < $1.time }
        let place = (rows.firstIndex { $0.you } ?? 0) + 1
        return VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 8) {
                    Text("#\(i + 1)")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.sgsMuted)
                        .frame(width: 30, alignment: .leading)
                    Text(r.name)
                        .font(.system(size: 15, weight: r.you ? .heavy : .regular))
                    Spacer()
                    Text(RaceScene.fmtTime(r.time))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(r.you ? Color.sgsAccent.opacity(0.22) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(r.you ? Color.sgsAccent.opacity(0.5) : Color.clear, lineWidth: 1))
            }
            Text("You placed #\(place) of \(rows.count)")
                .font(.system(size: 14))
                .foregroundStyle(Color.sgsMuted)
                .padding(.top, 2)
        }
    }
}
