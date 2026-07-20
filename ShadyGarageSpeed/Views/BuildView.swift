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

    var body: some View {
        GeometryReader { geo in
            let landscapePhone = geo.size.height < 520
            let portraitPhone = !landscapePhone && geo.size.width < 700
            ZStack {
                SceneKitView(controller: scene)
                    .ignoresSafeArea()

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
            .onAppear {
                scene.portraitFraming = portraitPhone
                scene.refreshCustomCar()
            }
            .onChange(of: geo.size) { _, newSize in
                scene.portraitFraming = newSize.height >= 520 && newSize.width < 700
            }
        }
    }

    private var panel: some View {
        Panel {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("🔧 Build Bay")
                            .font(.system(size: 17, weight: .heavy))
                        Spacer()
                        Text("💰 $\(game.cash)")
                            .font(.system(size: 15, weight: .bold))
                            .accessibilityIdentifier("build-cash")
                    }

                    VStack(spacing: 7) {
                        StatBar(name: "Speed", value: game.computeStats().speed)
                        StatBar(name: "Accel", value: game.computeStats().accel)
                        StatBar(name: "Handling", value: game.computeStats().handling)
                    }

                    let L = game.car.chassis
                    let cost = game.chassisCost(L)
                    HStack {
                        Text("Chassis: **Lv\(L) \(GameState.chassisNames[L])**")
                            .font(.system(size: 14))
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
                        if game.inventory.isEmpty {
                            Text("No parts yet. Steal some from customers, or buy from the Catalog…")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.sgsMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 10)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(Array(game.inventory.enumerated()), id: \.element.id) { i, part in
                                    invCard(part, index: i)
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
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let p = game.car.parts[type] {
                TierBadge(tier: p.tier)
            } else {
                Text("Empty")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.sgsMuted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func invCard(_ part: Part, index: Int) -> some View {
        let price = Int((Double(game.partSellPrice(part.tier)) * game.sellMult).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(GameState.partIcons[part.type] ?? "")
                    .font(.system(size: 20))
                TierBadge(tier: part.tier)
                Spacer()
            }
            Text(GameState.partLabels[part.type] ?? part.type)
                .font(.system(size: 13, weight: .bold))
            HStack(spacing: 6) {
                SGSButton(title: "Install", tiny: true, a11y: "install-\(index)") { scene.installPart(part.id) }
                SGSButton(title: "Sell $\(price)", ghost: true, tiny: true, a11y: "sell-\(index)") { scene.sellPart(part.id) }
            }
        }
        .padding(10)
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Catalog card: one part type, buy buttons for Sport/Pro/Elite tiers.
    private func catalogCard(_ type: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(GameState.partIcons[type] ?? "")
                    .font(.system(size: 20))
                Text(GameState.partLabels[type] ?? type)
                    .font(.system(size: 13, weight: .bold))
                Spacer()
            }
            ForEach([2, 3, 4], id: \.self) { tier in
                let price = GameState.catalogPrices[tier] ?? 0
                HStack {
                    TierBadge(tier: tier)
                    Spacer()
                    SGSButton(title: "$\(price)", tiny: true,
                              disabled: game.cash < price,
                              a11y: "catalog-buy-\(type)-\(tier)") {
                        scene.buyPart(type, tier)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.sgsCard2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
