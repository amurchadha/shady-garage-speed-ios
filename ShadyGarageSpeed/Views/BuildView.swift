// BuildView.swift — build bay HUD (mirrors #screen-build):
// stat bars, chassis upgrade, part slots, inventory install/sell.
// Layout mirrors the web CSS: left panel on wide screens, bottom sheet on
// portrait phones, right panel on landscape phones.
import SwiftUI

struct BuildView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var scene: BuildScene
    @ObservedObject var game: GameState

    private enum BuildTab { case inventory, catalog }
    /// Debug launch arg `-catalog` opens the Catalog tab directly (screenshots/tests).
    @State private var tab: BuildTab =
        ProcessInfo.processInfo.arguments.contains("-catalog") ? .catalog : .inventory
    /// #66 Pro/Elite sell confirmation (alert carries the fence price).
    @State private var confirmSell: Part? = nil

    var body: some View {
        GeometryReader { geo in
            let landscapePhone = geo.size.height < 520
            let portraitPhone = !landscapePhone && geo.size.width < 700
            ZStack {
                SceneKitView(controller: scene, fps: 30, thermal: app.thermalLimited)
                    .ignoresSafeArea()
                    .accessibilityHidden(true) // visual-only; state lives in the panel

                if landscapePhone {
                    HStack {
                        Spacer()
                        panel
                            .frame(width: min(360, geo.size.width * 0.5))
                            .padding(.trailing, 10)
                            .padding(.vertical, 8)
                    }
                } else if portraitPhone {
                    VStack {
                        Spacer()
                        panel
                            .frame(maxHeight: geo.size.height * 0.55)
                            .padding(.horizontal, 10)
                            .padding(.bottom, 6)
                    }
                } else {
                    HStack {
                        panel
                            .frame(width: min(430, geo.size.width * 0.45))
                            .padding(.leading, 10)
                            .padding(.vertical, 8)
                        Spacer()
                    }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility3) // panel grows to A11y XL
            .onAppear {
                scene.portraitFraming = portraitPhone
                scene.refreshCustomCar()
            }
            .onChange(of: geo.size) { _, newSize in
                scene.portraitFraming = newSize.height >= 520 && newSize.width < 700
            }
            // #66 Pro/Elite sales confirm first (Stock/Sport sell instantly)
            .alert("Sell part?", isPresented: Binding(get: { confirmSell != nil },
                                                      set: { if !$0 { confirmSell = nil } })) {
                Button("Sell", role: .destructive) {
                    if let p = confirmSell { scene.sellPart(p.id) }
                    confirmSell = nil
                }
                .accessibilityIdentifier("sell-confirm")
                Button("Cancel", role: .cancel) { confirmSell = nil }
            } message: {
                if let p = confirmSell {
                    Text("Sell \(GameState.tierNames[p.tier]) \(GameState.partLabels[p.type] ?? p.type) for $\(game.fencePrice(p))?")
                }
            }
        }
    }

    private var panel: some View {
        Panel {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("🔧 Build Bay")
                            .font(sgsFont(17, .heavy))
                        Spacer()
                        Text("💰 $\(game.cash)")
                            .font(sgsFont(15, .bold))
                            .accessibilityIdentifier("build-cash")
                    }

                    VStack(spacing: 7) {
                        StatBar(name: "Speed", value: game.computeStats().speed)
                        StatBar(name: "Accel", value: game.computeStats().accel)
                        StatBar(name: "Handling", value: game.computeStats().handling)
                    }

                    // contracts board: one active order at a time
                    if let c = game.contract {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("📜 Contract")
                                        .font(sgsFont(12, .black))
                                    let rk = GameState.contractRanks[c.rank] ?? GameState.contractRanks["standard"]!
                                    Text(rk.badge)
                                        .font(sgsFont(10, .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background((c.rank == "rush" ? Color.sgsBad : c.rank == "premium" ? Color(rgb: 0xa855f7) : Color.sgsMuted).opacity(0.25))
                                        .foregroundStyle(c.rank == "rush" ? Color.sgsBad : c.rank == "premium" ? Color(rgb: 0xa855f7) : Color.sgsMuted)
                                        .clipShape(Capsule())
                                }
                                Text("\(GameState.tierNames[c.minTier]) \(GameState.partLabels[c.type] ?? c.type) · by Day \(c.deadline)")
                                    .font(sgsFont(12))
                                    .foregroundStyle(Color.sgsMuted)
                                Text("Reward: $\(c.reward)")
                                    .font(sgsFont(12, .bold))
                                    .foregroundStyle(Color.sgsGood)
                            }
                            Spacer()
                            SGSButton(title: "Fulfill", small: true,
                                      disabled: !game.inventory.contains { $0.type == c.type && $0.tier >= c.minTier },
                                      a11y: "contract-fulfill",
                                      hint: "Hands over the part and collects the reward") {
                                scene.fulfillContract()
                            }
                        }
                        .padding(10)
                        .background(Color.sgsCard2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("contract-card")
                    }

                    let L = game.car.chassis
                    let cost = game.chassisCost(L)
                    HStack {
                        Text("Chassis: **Lv\(L) \(GameState.chassisNames[L])**")
                            .font(sgsFont(14))
                        Spacer()
                        if let cost {
                            SGSButton(title: "Upgrade $\(cost)", small: true,
                                      disabled: game.cash < cost, a11y: "chassis-upgrade") {
                                scene.upgradeChassis()
                            }
                        } else {
                            SGSButton(title: "MAX", small: true, disabled: true, a11y: "chassis-upgrade") {}
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(GameState.partTypes, id: \.self) { type in
                            slot(type)
                        }
                    }

                    HStack(spacing: 8) {
                        SGSButton(title: "Inventory", ghost: tab != .inventory, small: true,
                                  a11y: "tab-inventory") { tab = .inventory }
                        SGSButton(title: "Catalog", ghost: tab != .catalog, small: true,
                                  a11y: "tab-catalog") { tab = .catalog }
                    }

                    if tab == .inventory {
                        invControls // #67 bulk sell + #68 filter chips / sort toggle
                        if game.inventory.isEmpty {
                            Text("No parts yet. Steal some from customers, or buy from the Catalog…")
                                .font(sgsFont(13))
                                .foregroundStyle(Color.sgsMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                        } else if displayInventory.isEmpty {
                            Text("Nothing at this tier.")
                                .font(sgsFont(13))
                                .foregroundStyle(Color.sgsMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                        } else {
                            // NON-lazy 2-column grid: lazy grids keep off-screen rows out
                            // of the accessibility tree (VoiceOver + XCUITest) entirely.
                            VStack(spacing: 8) {
                                ForEach(Array(stride(from: 0, to: displayInventory.count, by: 2)), id: \.self) { row in
                                    HStack(spacing: 8) {
                                        invCard(displayInventory[row], index: row)
                                        if row + 1 < displayInventory.count {
                                            invCard(displayInventory[row + 1], index: row + 1)
                                        } else {
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(GameState.partTypes, id: \.self) { type in
                                catalogCard(type)
                            }
                        }
                    }

                    SGSButton(title: "← Back to Garage", a11y: "build-back") { app.backToGarage() }
                }
            }
        }
    }

    private func slot(_ type: String) -> some View {
        HStack {
            Text("\(GameState.partIcons[type] ?? "") \(GameState.partLabels[type] ?? type)")
                .font(sgsFont(13, .semibold))
            Spacer()
            if let p = game.car.parts[type] {
                TierBadge(tier: p.tier)
            } else {
                Text("Empty")
                    .font(sgsFont(11))
                    .foregroundStyle(Color.sgsMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func invCard(_ part: Part, index: Int) -> some View {
        let price = game.fencePrice(part)
        let d = game.demand(part.type, day: game.day)
        let arrow = d > 1.05 ? "▲" : d < 0.95 ? "▼" : ""
        let hot = part.stolenDay == game.day
        let partName = "\(GameState.tierNames[part.tier]) \(GameState.partLabels[part.type] ?? part.type)"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(GameState.partIcons[part.type] ?? "")
                    .font(.system(size: 20))
                    .accessibilityHidden(true) // decorative emoji
                TierBadge(tier: part.tier)
                if hot {
                    Text("HOT")
                        .font(sgsFont(9, .black))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.sgsBad.opacity(0.25))
                        .foregroundStyle(Color.sgsBad)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            Text(GameState.partLabels[part.type] ?? part.type)
                .font(sgsFont(13, .bold))
            HStack(spacing: 6) {
                SGSButton(title: "Install", tiny: true, a11y: "install-\(index)",
                          label: "Install \(partName)") { scene.installPart(part.id) }
                SGSButton(title: "Sell $\(price)\(arrow.isEmpty ? "" : " \(arrow)")", ghost: true, tiny: true,
                          a11y: "sell-\(index)",
                          label: "Sell \(partName) for $\(price)") {
                              // #66 Pro/Elite sales confirm first (Stock/Sport sell instantly)
                              if part.tier >= 3 { confirmSell = part } else { scene.sellPart(part.id) }
                          }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading) // equal-width grid cells
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    // MARK: #67 bulk sell + #68 inventory filter/sort

    /// #68 filter by tier, then sort (tier desc | type A→Z with tier-desc tiebreak).
    private var displayInventory: [Part] {
        var inv = game.inventory
        if game.invFilter > 0 { inv = inv.filter { $0.tier == game.invFilter } }
        inv.sort { a, b in
            let la = GameState.partLabels[a.type] ?? a.type
            let lb = GameState.partLabels[b.type] ?? b.type
            if game.invSort == "type" { return la != lb ? la < lb : a.tier > b.tier }
            return a.tier != b.tier ? a.tier > b.tier : la < lb
        }
        return inv
    }

    private var stockParts: [Part] { game.inventory.filter { $0.tier == 1 } }

    private var invControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0...4, id: \.self) { t in
                    SGSButton(title: t == 0 ? "All" : "T\(t)", ghost: game.invFilter != t,
                              tiny: true, a11y: "inv-filter-\(t)") { game.invFilter = t }
                }
                Spacer()
                SGSButton(title: game.invSort == "tier" ? "Sort: tier ▾" : "Sort: type ▾",
                          ghost: true, tiny: true, a11y: "inv-sort",
                          hint: "Toggle sort order") {
                    game.invSort = game.invSort == "tier" ? "type" : "tier"
                }
            }
            let total = stockParts.reduce(0) { $0 + game.fencePrice($1) }
            SGSButton(title: stockParts.isEmpty ? "Sell Stock"
                                                 : "Sell Stock (\(stockParts.count) · $\(total))",
                      small: true, disabled: stockParts.isEmpty, a11y: "bulk-sell",
                      hint: "Sell every Stock (tier 1) part at once") { scene.sellStock() }
        }
    }

    /// Catalog card: one part type, buy buttons for Sport/Pro/Elite tiers.
    private func catalogCard(_ type: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(GameState.partIcons[type] ?? "")
                    .font(.system(size: 20))
                    .accessibilityHidden(true) // decorative emoji
                Text(GameState.partLabels[type] ?? type)
                    .font(sgsFont(13, .bold))
                Spacer()
            }
            ForEach([2, 3, 4], id: \.self) { tier in
                let price = GameState.catalogPrices[tier] ?? 0
                HStack {
                    TierBadge(tier: tier)
                    Spacer()
                    SGSButton(title: "$\(price)", tiny: true,
                              disabled: game.cash < price,
                              a11y: "catalog-buy-\(type)-\(tier)",
                              label: "Buy \(GameState.tierNames[tier]) \(GameState.partLabels[type] ?? type) for $\(price)") {
                        scene.buyPart(type, tier)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}
