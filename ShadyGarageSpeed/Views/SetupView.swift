// SetupView.swift — new-game setup: name + partner pick (mirrors #screen-setup).
import SwiftUI

struct SetupView: View {
    @EnvironmentObject var app: AppState
    @State private var name = "Boss"
    @State private var selected = 0
    /// #76 ⓘ bio sheet (friend index + visibility)
    @State private var bioInfo: Int? = nil
    @State private var showBio = false

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
                        .accessibilityIdentifier("setup-name")
                // NOTE: no per-keystroke length cap — the 14-char cap is applied
                // on commit in newGame(), so IME composition is never truncated.
                }

                Text("Pick your partner — each has a perk:")
                    .foregroundStyle(Color.sgsMuted)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(GameState.friends.indices, id: \.self) { i in
                        friendCard(i)
                    }
                }
                .sheet(isPresented: $showBio) {
                    if let i = bioInfo { CrewSheet(friend: i) }
                }

                HStack {
                    SGSButton(title: "Back", ghost: true, a11y: "setup-back") { app.goMenu() }
                    Spacer()
                    SGSButton(title: "Start Day 1", big: true, a11y: "start-day1") {
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

    /// Partner card: tap selects, the ⓘ corner opens the #76 bio sheet.
    private func friendCard(_ i: Int) -> some View {
        let f = GameState.friends[i]
        return ZStack(alignment: .topTrailing) {
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
                    .font(sgsFont(13, .bold))
                    .foregroundStyle(Color.sgsAccent)
                Text(f.desc)
                    .font(sgsFont(12))
                    .foregroundStyle(Color.sgsMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                AudioEngine.shared.click()
                selected = i
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(f.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("friend-card-\(i)")
            Button { bioInfo = i; showBio = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.sgsMuted)
                    .padding(8)
            }
            .accessibilityLabel("\(f.name) bio")
            .accessibilityIdentifier("bio-info-\(i)")
        }
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(i == selected ? Color.sgsAccent : Color.white.opacity(0.08),
                    lineWidth: i == selected ? 2.5 : 1))
    }
}
