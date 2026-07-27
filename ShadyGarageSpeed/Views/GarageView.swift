// GarageView.swift — garage phase HUD (mirrors #screen-garage):
// topbar (day/cash/suspicion/heat + nav), prompt, job panel, cop modal, steal minigame.
import SwiftUI
import SceneKit

struct GarageView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var scene: GarageScene
    @ObservedObject var game: GameState
    @ObservedObject private var audio = AudioEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Debug launch arg `-laddersheet` opens the rival ladder directly (screenshots).
    @State private var showLadder = ProcessInfo.processInfo.arguments.contains("-laddersheet")
    /// Debug launch arg `-crewsheet` opens the hire sheet directly (screenshots).
    @State private var showCrew = ProcessInfo.processInfo.arguments.contains("-crewsheet")
    @State private var showSettings = ProcessInfo.processInfo.arguments.contains("-settingsheet")
    /// First-run tutorial coach marks (persisted tutorialSeen flag).
    @State private var coachIdx = -1
    private static let coachMarks = [
        "Customers bring you cars. Fix for cash — or Steal for parts.",
        "Watch SUSPICION (this customer) and HEAT (the cops).",
        "Build your racer in the Build Bay, then beat the rivals.",
    ]
    /// Cash count-up tween state (juice): shownCash chases game.cash.
    @State private var shownCash = 0
    @State private var cashTimer: Timer?

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 520
            ZStack(alignment: .top) {
                SceneKitView(controller: scene, onTap: { pt, view in
                    scene.handleTap(pt, view)
                }, fps: 30, thermal: app.thermalLimited)
                .ignoresSafeArea()
                .accessibilityHidden(true) // visual-only; state lives in the HUD

                VStack(spacing: 8) {
                    topbar(narrow: geo.size.width < 700)
                    if !scene.prompt.isEmpty {
                        Text(scene.prompt)
                            .font(sgsFont(14, .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.sgsPanel)
                            .clipShape(Capsule())
                            .transition(.opacity)
                            .accessibilityIdentifier("garage-prompt")
                    }
                    if scene.debugHUD {
                        Text("cars:\(scene.carCount)")
                            .font(sgsFont(10, .bold, mono: true))
                            .foregroundStyle(Color.sgsMuted)
                            .accessibilityIdentifier("debug-cars")
                    }
                    Spacer()
                    if !compact {
                        jobPanel(maxHeight: geo.size.height * 0.45)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 6)

                if compact, scene.customer != nil {
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            jobPanel(maxHeight: geo.size.height * 0.62)
                                .frame(width: min(340, geo.size.width * 0.46))
                            Spacer()
                        }
                        .padding(.trailing, 8)
                    }
                }

                if let idx = scene.pendingStealIndex, let c = scene.customer, c.parts.indices.contains(idx) {
                    StealMinigameView(
                        title: "Swap the \((GameState.partLabels[c.parts[idx].type] ?? "part").lowercased())…",
                        tier: c.parts[idx].tier, heat: game.heat, diffGreen: game.diffMods.green,
                        onResolve: { zone in scene.resolveSteal(zone) }
                    )
                }

                // speech bubble over the owner avatar (world-projected position)
                if let bubble = scene.bubbleText {
                    SpeechBubble(text: bubble)
                        .position(x: scene.bubblePos.x, y: scene.bubblePos.y - 28)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: scene.bubbleText)
                        .allowsHitTesting(false)
                }

                // Daily Lugnut tabloid card (tap or 3.5s to dismiss; non-blocking)
                if let headline = scene.lugnut {
                    VStack(spacing: 4) {
                        Text("THE DAILY LUGNUT")
                            .font(sgsFont(12, .black))
                            .tracking(2)
                            .foregroundStyle(Color.sgsBad)
                        Text(headline)
                            .font(sgsFont(13, .bold))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(rgb: 0xf5f0e6))
                    .foregroundStyle(Color(rgb: 0x1f2937))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                    .rotationEffect(.degrees(-1.5))
                    .padding(.top, 92)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .onTapGesture { scene.dismissLugnut() }
                    .accessibilityIdentifier("lugnut-card")
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }

                // floating "+$X" cash pops near the cash readout
                HStack(spacing: 6) {
                    ForEach(app.toasts.cashPops) { t in
                        CashPopView(text: t.text, negative: t.kind == .bad)
                    }
                }
                .padding(.leading, 120)
                .padding(.top, 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                // first-run tutorial card (3 coach marks, Next/Skip, never again)
                if coachIdx >= 0 {
                    VStack(spacing: 10) {
                        Text(Self.coachMarks[coachIdx])
                            .font(sgsFont(15, .semibold))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            SGSButton(title: "Skip", ghost: true, small: true,
                                      a11y: "tutorial-skip") { endTutorial() }
                            SGSButton(title: coachIdx == Self.coachMarks.count - 1 ? "Got it" : "Next",
                                      small: true, a11y: "tutorial-next") {
                                coachIdx += 1
                                if coachIdx >= Self.coachMarks.count { endTutorial() }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 320)
                    .background(Color.sgsCard)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.sgsAccent.opacity(0.6), lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
                    .padding(.bottom, 90)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("tutorial-card")
                    .transition(.opacity)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility3) // content grows to A11y XL
            .onAppear {
                // NOTE: enterPlay is owned by AppState (single source) — calling it
                // here too used to double-enter and could spawn a ghost customer car.
                scene.portraitFraming = geo.size.height > geo.size.width
                shownCash = game.cash
                if !game.tutorialSeen && coachIdx < 0 { coachIdx = 0 } // first-run coach marks
            }
            .onChange(of: geo.size) { _, newSize in
                scene.portraitFraming = newSize.height > newSize.width
            }
            .onChange(of: game.cash) { _, v in stepCash(to: v) }
            .sheet(isPresented: $showLadder) {
                LadderSheet(game: game)
            }
            .sheet(isPresented: $showCrew) {
                HireSheet(game: game)
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(game: game)
            }
            .sheet(isPresented: $app.showTrackSheet) {
                TrackSelectSheet(game: game)
            }
            .sheet(isPresented: Binding(get: { scene.showCopModal },
                                        set: { scene.showCopModal = $0 })) {
                copModal
                    .presentationDetents([.medium])
                    .presentationBackground(.ultraThinMaterial)
                    .interactiveDismissDisabled(true) // a choice is required to continue
            }
        }
    }

    // MARK: topbar

    private func endTutorial() {
        coachIdx = -1
        game.tutorialSeen = true // persisted — coach marks never show again
        game.save()
    }

    /// Cash count-up tween: shownCash chases game.cash at ~30Hz (juice).
    /// Instant under Reduce Motion.
    private func stepCash(to v: Int) {
        if reduceMotion {
            shownCash = v
            return
        }
        cashTimer?.invalidate()
        cashTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { t in
            let diff = v - shownCash
            if diff == 0 {
                t.invalidate()
                cashTimer = nil
                return
            }
            let s = max(1, abs(diff) / 4)
            shownCash = abs(diff) <= s ? v : shownCash + (diff > 0 ? s : -s)
        }
    }

    private func topbar(narrow: Bool) -> some View {
        Panel {
            if narrow {
                // portrait phones: three rows (web .topbar wraps the same way)
                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text("📅 Day \(game.day)")
                            .font(sgsFont(13, .semibold))
                            .fixedSize()
                            .accessibilityIdentifier("hud-day")
                        Text("💰 $\(shownCash)")
                            .font(sgsFont(13, .semibold))
                            .fixedSize()
                            .accessibilityIdentifier("hud-cash")
                        Spacer()
                        SGSButton(title: "", small: true, a11y: "nav-build",
                                  systemImage: "wrench.fill", label: "Build bay") { app.goBuild() }
                        SGSButton(title: "", small: true, a11y: "nav-race",
                                  systemImage: "flag.checkered", label: "Race") { app.goRace() }
                    }
                    HStack(spacing: 14) {
                        Spacer()
                        meter("Suspicion", value: game.suspicion,
                              color: game.suspicion >= 90 ? .sgsBad : game.suspicion >= 50 ? .sgsWarn : .sgsGood,
                              barWidth: 64, a11y: "hud-suspicion")
                        meter("Heat", value: game.heat,
                              color: Color(rgb: 0xf97316), barWidth: 64, a11y: "hud-heat")
                        Spacer()
                    }
                    HStack(spacing: 14) {
                        Spacer()
                        SGSButton(title: "", small: true, a11y: "nav-menu",
                                  systemImage: "house.fill", label: "Main menu") { app.goMenu() }
                        SGSButton(title: "", small: true, a11y: "mute-toggle",
                                  systemImage: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  label: audio.muted ? "Unmute" : "Mute") { audio.toggleMute() }
                        SGSButton(title: "", small: true, a11y: "nav-ladder",
                                  systemImage: "trophy.fill", label: "Rival ladder") { showLadder = true }
                        SGSButton(title: "", small: true, a11y: "nav-crew",
                                  systemImage: "person.2.fill", label: "Hire crew") { showCrew = true }
                        SGSButton(title: "", small: true, a11y: "nav-settings",
                                  systemImage: "gearshape.fill", label: "Settings") { showSettings = true }
                        Spacer()
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Text("📅 Day \(game.day)")
                        .font(sgsFont(14, .semibold))
                        .fixedSize()
                        .accessibilityIdentifier("hud-day")
                    Text("💰 $\(shownCash)")
                        .font(sgsFont(14, .semibold))
                        .fixedSize()
                        .accessibilityIdentifier("hud-cash")
                    Spacer()
                    meter("Suspicion", value: game.suspicion,
                          color: game.suspicion >= 90 ? .sgsBad : game.suspicion >= 50 ? .sgsWarn : .sgsGood,
                          barWidth: 60, a11y: "hud-suspicion")
                    meter("Heat", value: game.heat,
                          color: Color(rgb: 0xf97316), barWidth: 60, a11y: "hud-heat")
                    Spacer()
                    SGSButton(title: "", small: true, a11y: "mute-toggle",
                              systemImage: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                              label: audio.muted ? "Unmute" : "Mute") { audio.toggleMute() }
                    SGSButton(title: "Ladder", small: true, a11y: "nav-ladder",
                              systemImage: "trophy.fill", label: "Rival ladder") { showLadder = true }
                    SGSButton(title: "Crew", small: true, a11y: "nav-crew",
                              systemImage: "person.2.fill", label: "Hire crew") { showCrew = true }
                    SGSButton(title: "Menu", ghost: true, small: true, a11y: "nav-menu",
                              systemImage: "house.fill") { app.goMenu() }
                    SGSButton(title: "", small: true, a11y: "nav-settings",
                              systemImage: "gearshape.fill", label: "Settings") { showSettings = true }
                    SGSButton(title: "Build", small: true, a11y: "nav-build",
                              systemImage: "wrench.fill") { app.goBuild() }
                    SGSButton(title: "Race", small: true, a11y: "nav-race",
                              systemImage: "flag.checkered") { app.goRace() }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2) // topbar grows to A11y L, capped
    }

    private func meter(_ title: String, value: Int, color: Color, barWidth: CGFloat,
                       a11y: String? = nil) -> some View {
        let w = barWidth
        return HStack(spacing: 5) {
            Text(title)
                .font(sgsFont(10, .bold))
                .foregroundStyle(Color.sgsMuted)
                .textCase(.uppercase)
                .accessibilityHidden(true) // the combined label carries the meaning
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color)
                    .frame(width: w * CGFloat(min(100, max(0, value))) / 100)
            }
            .frame(width: w, height: 10)
            .accessibilityHidden(true) // decorative bar
            Text("\(min(100, max(0, value)))")
                .font(sgsFont(12, .heavy))
                .frame(minWidth: 20, alignment: .leading)
                .accessibilityIdentifier(a11y ?? "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) \(min(100, max(0, value))) of 100")
        .accessibilityAddTraits(.updatesFrequently)
    }

    // MARK: job panel

    private func chip(_ text: String, color: Color, a11y: String) -> some View {
        Text(text)
            .font(sgsFont(11, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .clipShape(Capsule())
            .accessibilityIdentifier(a11y)
    }

    private func jobPanel(maxHeight: CGFloat) -> some View {
        Group {
            if let c = scene.customer {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("\(c.name)’s Car")
                                .font(sgsFont(16, .heavy))
                            let badge = GameState.archBadge(c.archetype)
                            if !badge.isEmpty {
                                Text(badge)
                                    .font(sgsFont(15))
                                    .accessibilityIdentifier("arch-badge")
                            }
                            if c.golden {
                                Text("✨")
                                    .font(sgsFont(15))
                                    .accessibilityIdentifier("golden-badge")
                            }
                            Spacer()
                            if scene.ownerWatching {
                                chip("👁 watching", color: .sgsBad, a11y: "watch-chip")
                            }
                            if let left = scene.rushedRemaining {
                                chip("⏱ \(left)s", color: left > 0 ? .sgsWarn : .sgsMuted,
                                     a11y: "rushed-chip")
                            }
                        }
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(Array(c.parts.enumerated()), id: \.element.id) { i, p in
                                    jobRow(i: i, p: p)
                                }
                            }
                        }
                        .frame(maxHeight: maxHeight)
                        HStack {
                            Text("Job total: **$\(scene.jobTotal)**")
                                .font(sgsFont(15))
                                .accessibilityIdentifier("job-total")
                            Spacer()
                            SGSButton(title: "Finish Job", disabled: scene.jobActions < 1,
                                      a11y: "finish-job") {
                                scene.finishJob()
                            }
                        }
                    }
                }
            }
        }
    }

    private func jobRow(i: Int, p: CustomerPart) -> some View {
        let cond = p.stolen ? "Swapped (Stock)" : p.fixed ? "Fixed ✓"
            : p.needsService ? "Worn – needs service" : "OK"
        let condOK = p.stolen || p.fixed || !p.needsService
        let selected = scene.selectedPart == p.type
        let partName = "\(GameState.partLabels[p.type] ?? p.type), \(GameState.tierNames[p.tier]) tier"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text("\(GameState.partIcons[p.type] ?? "") \(GameState.partLabels[p.type] ?? p.type)")
                    .font(sgsFont(14, .bold))
                TierBadge(tier: p.tier)
                Spacer()
                Text(cond)
                    .font(sgsFont(11))
                    .foregroundStyle(condOK ? Color.sgsGood : Color.sgsWarn)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6) // shrink instead of clipping at huge text sizes
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                SGSButton(title: "Fix", tiny: true, disabled: !p.needsService || p.fixed,
                          a11y: "fix-\(i)",
                          label: "Fix \(partName)", hint: "Repairs this part") {
                    scene.fixPart(i)
                }
                SGSButton(title: "Steal", tiny: true,
                          tint: scene.ownerWatching ? Color.sgsBad : Color(rgb: 0x7c3aed),
                          disabled: p.stolen, a11y: "steal-\(i)",
                          label: "Steal \(partName)", hint: "Opens the timing minigame") {
                    scene.stealPart(i)
                }
                if p.tier == 1 && !p.stolen {
                    Text("stock – not worth stealing")
                        .font(sgsFont(10))
                        .italic()
                        .foregroundStyle(Color.sgsMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(9)
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(selected ? Color.sgsAccent : Color.clear, lineWidth: 1.5))
        .accessibilityElement(children: .contain) // sensible VoiceOver reading order
        .onTapGesture { scene.selectedPart = p.type }
    }

    // MARK: cop modal (presented as a true .sheet)

    private var copModal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🚨 Cops are sniffing around the garage.")
                .font(.title3.bold())
            Text("Word is out that stolen parts move through here. Handle this quietly…")
                .foregroundStyle(Color.sgsMuted)
            if scene.copExplain {
                Text("First visit? Heat at 70+ brings cops around. Bribe to cool off fast, or lay low and lose a day.")
                    .font(sgsFont(13, .semibold))
                    .foregroundStyle(Color.sgsWarn)
            }
            HStack {
                Spacer()
                SGSButton(title: "Pay $200 bribe", disabled: !scene.canBribe,
                          a11y: "cop-bribe",
                          hint: "The cops leave and heat drops by 50") {
                    scene.copBribe()
                }
                SGSButton(title: "Lay low", ghost: true, a11y: "cop-laylow",
                          hint: "Skip a day, heat drops by 25") {
                    scene.copLayLow()
                }
            }
        }
        .padding(24)
        .foregroundStyle(Color.sgsText)
    }
}
