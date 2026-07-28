// MetaSheets.swift — social/meta sheets (#73 gallery, #74 stats, #75 HoF,
// #76 bios, #79 credits, #80 what's-new). All follow the sheet conventions:
// presentationDetents + .ultraThinMaterial, kebab-case a11y ids.
import SwiftUI

// MARK: - #73 achievements gallery

struct AchievementsSheet: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🏅 Achievements — \(game.achievements.count)/\(Achievements.table.count)")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "achv-close") { dismiss() }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Achievements.table, id: \.id) { entry in
                        let got = game.achievements.contains(entry.id)
                        HStack(spacing: 10) {
                            Text(got ? entry.def.icon : "🔒")
                                .font(.title3)
                                .frame(width: 34)
                                .accessibilityHidden(true) // state reads from the text
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.def.name)
                                    .font(sgsFont(15, .bold))
                                    .foregroundStyle(got ? Color.sgsText : Color.sgsMuted)
                                Text(entry.def.desc)
                                    .font(sgsFont(12))
                                    .foregroundStyle(Color.sgsMuted)
                            }
                            Spacer()
                            if got {
                                Text("✓")
                                    .font(sgsFont(15, .black))
                                    .foregroundStyle(Color.sgsGood)
                            }
                        }
                        .padding(10)
                        .background(got ? Color.sgsCard2 : Color.sgsCard2.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("achv-\(entry.id)")
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(Color.sgsText)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - #74 lifetime stats

struct StatsSheet: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.sgsMuted)
            Spacer()
            Text(value).font(sgsFont(15, .bold))
        }
        .font(sgsFont(14))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📊 Lifetime Stats")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "stats-close") { dismiss() }
            }
            ScrollView {
                VStack(spacing: 8) {
                    let s = game.stats
                    row("Customers served", "\(game.customersServed)")
                    row("Parts fixed", "\(s.fixes)")
                    row("Parts stolen", "\(s.steals)")
                    row("Customers enraged", "\(s.rages)")
                    row("Raids survived", "\(s.raids)")
                    row("Lifetime earnings", "$\(s.earnings)")
                    row("Races finished", "\(s.races)")
                    row("Contracts fulfilled", "\(s.contractsDone)")
                    let h = s.playtimeSec / 3600, m = (s.playtimeSec % 3600) / 60
                    row("Time in the garage", h > 0 ? "\(h)h \(m)m" : "\(m)m")
                    if let fav = s.archSeen.max(by: { $0.value < $1.value }), fav.value > 0 {
                        row("Favorite customer", fav.key.capitalized)
                    }
                    Divider().overlay(Color.white.opacity(0.15))
                    ForEach(GameState.tracks, id: \.id) { t in
                        row("Best — \(t.name)", RaceScene.fmtTime(game.bestLaps[t.id]))
                        row("Best — \(t.name) ⇄", RaceScene.fmtTime(game.bestLaps[t.id + "R"]))
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(Color.sgsText)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - #75 Hall of Fame

struct HallOfFameSheet: View {
    @ObservedObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🏆 Hall of Fame")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "hof-close") { dismiss() }
            }
            if game.hof.isEmpty {
                Text("No finished runs yet. Go race!")
                    .font(sgsFont(14))
                    .foregroundStyle(Color.sgsMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(game.hof) { r in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(r.legend ? "🏆" : "#\(r.place)")
                                        .font(sgsFont(15, .black))
                                        .frame(width: 34, alignment: .leading)
                                        .accessibilityHidden(true)
                                    Text(RaceScene.fmtTime(r.lap)).font(sgsFont(15, .bold))
                                    Text(trackLabel(r.track))
                                        .font(sgsFont(13))
                                        .foregroundStyle(Color.sgsMuted)
                                    Spacer()
                                    if let name = r.challengeName, let win = r.challengeWin {
                                        Text(win ? "beat \(name)" : "lost to \(name)")
                                            .font(sgsFont(12, .semibold))
                                            .foregroundStyle(win ? Color.sgsGood : Color.sgsBad)
                                    }
                                }
                                Text("\(Self.dateFmt.string(from: Date(timeIntervalSince1970: r.date / 1000))) · SPD \(r.speed) ACC \(r.accel) HDL \(r.handling)")
                                    .font(sgsFont(11))
                                    .foregroundStyle(Color.sgsMuted)
                            }
                            .padding(10)
                            .background(Color.sgsCard2)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("hof-row")
                        }
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(Color.sgsText)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
    }

    private func trackLabel(_ id: String) -> String {
        let rev = id.hasSuffix("R")
        let base = rev ? String(id.dropLast()) : id
        let name = GameState.tracks.first { $0.id == base }?.name ?? base
        return rev ? name + " ⇄" : name
    }
}

// MARK: - #76 crew bios

struct CrewSheet: View {
    /// nil → all four ("Meet the Crew"); otherwise just that friend (setup ⓘ).
    var friend: Int? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(friend == nil ? "👥 Meet the Crew" : "👤 \(GameState.friends[friend!].name)")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "crew-bio-close") { dismiss() }
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(GameState.friends.indices, id: \.self) { i in
                        if friend == nil || friend == i {
                            let f = GameState.friends[i]
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(Color(rgb: f.color))
                                        .frame(width: 40, height: 40)
                                        .overlay(Text(String(f.name.prefix(1)))
                                            .font(.system(size: 18, weight: .black))
                                            .foregroundStyle(.white))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(f.name).font(sgsFont(16, .bold))
                                        Text(f.tag)
                                            .font(sgsFont(12, .bold))
                                            .foregroundStyle(Color.sgsAccent)
                                        Text(f.desc)
                                            .font(sgsFont(12))
                                            .foregroundStyle(Color.sgsMuted)
                                    }
                                }
                                Text(f.bio)
                                    .font(sgsFont(13))
                                    .foregroundStyle(Color.sgsText)
                                Text("Best for: \(f.bestFor)")
                                    .font(sgsFont(12, .semibold))
                                    .foregroundStyle(Color.sgsMuted)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.sgsCard2)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("bio-card-\(i)")
                        }
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(Color.sgsText)
        .presentationDetents(friend == nil ? [.medium, .large] : [.medium])
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - #79 credits

struct CreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Credits")
                    .font(.title3.bold())
                Spacer()
                SGSButton(title: "Close", ghost: true, small: true, a11y: "credits-close") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("**Shady Garage & Speed** v\(GameState.appVersion) (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                Text("Made by one developer and an unreasonably large CI pipeline.")
                Text("Tech: SwiftUI + SceneKit + AVAudioEngine, zero downloaded assets — all geometry, UI, music and SFX are procedurally generated in code.")
                Text("Music & SFX: pre-rendered PCM buffers and oscillators, composed by a scheduler, not a musician.")
                Text("Reviewed by 124 adversarial agents. They found things.")
            }
            .font(sgsFont(14))
            .foregroundStyle(Color.sgsMuted)
            Spacer()
        }
        .padding(20)
        .foregroundStyle(Color.sgsText)
        .presentationDetents([.medium])
        .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - #80 What's-New card

struct WhatsNewCard: View {
    let version: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What's new in v\(version)")
                .font(sgsFont(16, .black))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Changelog.bullets(for: version), id: \.self) { b in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(b)
                    }
                    .font(sgsFont(13))
                }
            }
            HStack {
                Spacer()
                SGSButton(title: "Nice!", small: true, a11y: "whatsnew-dismiss", action: onDismiss)
            }
        }
        .padding(16)
        .frame(maxWidth: 420)
        .background(Color.sgsCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.sgsAccent.opacity(0.35), lineWidth: 1.5))
        .foregroundStyle(Color.sgsText)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whatsnew-card")
    }
}
