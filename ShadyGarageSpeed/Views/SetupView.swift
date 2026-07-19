// SetupView.swift — new-game setup: name + partner pick (mirrors #screen-setup).
import SwiftUI

struct SetupView: View {
    @EnvironmentObject var app: AppState
    @State private var name = "Boss"
    @State private var selected = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open Your Garage")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 6) {
                    Text("Your name")
                        .font(.headline)
                    TextField("Boss", text: $name)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(Color.sgsCard2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 2))
                        .frame(maxWidth: 260)
                        .onChange(of: name) { _, v in
                            if v.count > 14 { name = String(v.prefix(14)) }
                        }
                }

                Text("Pick your partner — each has a perk:")
                    .foregroundStyle(Color.sgsMuted)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(GameState.friends.indices, id: \.self) { i in
                        let f = GameState.friends[i]
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(Color(rgb: f.color))
                                    .frame(width: 52, height: 52)
                                Text(String(f.name.prefix(1)))
                                    .font(.system(size: 24, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            Text(f.name).font(.headline)
                            Text(f.tag)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.sgsAccent)
                            Text(f.desc)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.sgsMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.sgsCard2)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(i == selected ? Color.sgsAccent : Color.white.opacity(0.08),
                                    lineWidth: i == selected ? 2.5 : 1))
                        .onTapGesture {
                            AudioEngine.shared.click()
                            selected = i
                        }
                    }
                }

                HStack {
                    SGSButton(title: "Back", ghost: true) { app.goMenu() }
                    Spacer()
                    SGSButton(title: "Start Day 1", big: true) {
                        app.startNewGame(name, selected)
                    }
                }
                .padding(.top, 6)
            }
            .padding(24)
            .frame(maxWidth: 680)
            .background(Color.sgsCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Color.sgsText)
    }
}
