// GameState.swift — port of data.js: state, tiers, friends/perks, customers, persistence.
import Foundation
import Combine

// MARK: - Models

struct Part: Codable, Equatable, Identifiable {
    var id: String
    var type: String   // engine | turbo | exhaust | tires | suspension | bodykit
    var tier: Int      // 1..4
    var stolenDay: Int? = nil // set when fenced goods were stolen today (hot)
}

/// Contracts board: a typed part order with a deadline (day), rank, and cash reward.
struct Contract: Codable, Equatable {
    var type: String
    var minTier: Int
    var deadline: Int
    var reward: Int
    var rank: String = "standard" // standard | rush | premium
}

struct CarParts: Codable, Equatable {
    var engine: Part?
    var turbo: Part?
    var exhaust: Part?
    var tires: Part?
    var suspension: Part?
    var bodykit: Part?

    subscript(type: String) -> Part? {
        get {
            switch type {
            case "engine": return engine
            case "turbo": return turbo
            case "exhaust": return exhaust
            case "tires": return tires
            case "suspension": return suspension
            case "bodykit": return bodykit
            default: return nil
            }
        }
        set {
            switch type {
            case "engine": engine = newValue
            case "turbo": turbo = newValue
            case "exhaust": exhaust = newValue
            case "tires": tires = newValue
            case "suspension": suspension = newValue
            case "bodykit": bodykit = newValue
            default: break
            }
        }
    }
}

struct CarBuild: Codable, Equatable {
    var chassis: Int = 1
    var parts = CarParts()
}

struct CustomerPart: Codable, Equatable, Identifiable {
    var id: String
    var type: String
    var tier: Int
    var needsService: Bool
    var fixed: Bool = false
    var stolen: Bool = false
}

struct Customer: Codable, Equatable {
    var id: String
    var name: String
    var color: Int
    var parts: [CustomerPart]
    var archetype: String = "regular" // regular | rushed | skeptic | bigspender
    var bodyStyle: String = "sedan"   // sedan | hatch | truck
    var golden: Bool = false          // 3% golden customer: all parts ≥t3, ×3 pay
}

struct Stats: Equatable {
    var speed: Int
    var accel: Int
    var handling: Int
}

// MARK: - GameState

final class GameState: ObservableObject {
    @Published var playerName = "Boss"
    @Published var characterIndex = 0
    @Published var cash = 200
    @Published var day = 1
    @Published var inventory: [Part] = []
    @Published var car = CarBuild()
    @Published var bestLap: Double? = nil
    @Published var carValue = 0
    @Published var customersServed = 0
    @Published var suspicion = 0   // current customer's meter
    @Published var heat = 0        // cops' interest 0..100
    @Published var raceCount = 0
    @Published var ladder = 0      // pink-slip ladder: next rival 0–3, 4 = champion
    @Published var legend = false  // became Street Legend (ladder completed)

    // onboarding one-shots (persisted): heat explainer toast + cop modal line
    var heatHintShown = false
    var copHintShown = false

    /// Contracts board: active contract (offered every 3rd day advance if none).
    @Published var contract: Contract? = nil
    /// Hired crew (friend indices); perks apply from chosen character OR crew.
    @Published var crew: [Int] = []
    /// First-run coach marks shown (brand-new saves only).
    @Published var tutorialSeen = false
    /// Customers since a tier-4 part was last seen (drought breaker at 25).
    var elitePity = 0
    /// Per-track best lap seconds {classic: x, ridge: y, classicR: …(#20 reversed)}.
    @Published var bestLaps: [String: Double] = [:]
    /// #15 clean-job streak: consecutive jobs finished with zero steals (persisted).
    @Published var cleanStreak = 0
    /// #70 heat removed by the offline decay on the last load (session, for the toast).
    private(set) var offlineCool = 0
    /// #73 unlocked achievement ids (persisted; gallery + toasts read this).
    @Published var achievements: [String] = []
    /// #74 lifetime counters (persisted).
    @Published var stats = LifetimeStats()
    /// #75 Hall of Fame ring: last 10 finished runs, newest first (persisted).
    @Published var hof: [HofEntry] = []
    /// #72 today's best per track+dir; resets at midnight (persisted).
    @Published var daily = DailyBests()
    /// #80 last version the What's-New card was dismissed on (persisted).
    @Published var lastSeenVersion = ""

    /// AppState wires this: unlock → toast + fanfare.
    var onAchievement: ((AchievementDef) -> Void)?

    // MARK: #73 achievements (checker mirrors web checkAchievements)

    @discardableResult
    func unlock(_ id: String) -> Bool {
        guard let def = Achievements.byId[id], !achievements.contains(id) else { return false }
        achievements.append(id)
        save()
        onAchievement?(def)
        return true
    }

    func checkAchievements(_ event: AchEvent) {
        switch event {
        case .fix:       unlock("first_fix")
        case .steal:     unlock("first_steal")
        case .rage:      unlock("first_rage")
        case .customer:
            if customersServed >= 10 { unlock("cust_10") }
            if customersServed >= 50 { unlock("cust_50") }
        case .elitePart: unlock("first_elite")
        case .build:
            if GameState.partTypes.allSatisfy({ car.parts[$0]?.tier == 4 }) { unlock("full_elite") }
            if car.chassis >= 4 { unlock("max_chassis") }
        case .pinkslip:  unlock("first_pinkslip")
        case .legend:    unlock("street_legend")
        case .lap(let trackId, let lap):
            if trackId == "classic" && lap < 20 { unlock("sub20_classic") }
            if trackId == "ridge" && lap < 15 { unlock("sub15_ridge") }
        case .cash:
            if stats.earnings >= 1000 { unlock("earn_1k") }
            if stats.earnings >= 10000 { unlock("earn_10k") }
        case .cleanStreak: if cleanStreak >= 5 { unlock("clean_5") }
        case .combo(let n): if n >= 3 { unlock("combo_3") }
        case .contract:
            unlock("first_contract")
            if stats.contractsDone >= 5 { unlock("contracts_5") }
        case .crew:      unlock("crew_hire")
        case .raid:      unlock("raid_survive")
        }
    }

    /// #74 lifetime earnings counter + #73 earn thresholds (all cash-in events).
    func addEarnings(_ v: Int) {
        stats.earnings += max(0, v)
        checkAchievements(.cash)
    }

    // MARK: settings (persisted outside the save blob, like the web's sgs_settings)

    /// Chill / Normal / Cutthroat — drives the DIFF_TABLE multipliers.
    @Published var difficulty: String = UserDefaults.standard.string(forKey: "sgs_difficulty") ?? "normal" {
        didSet { UserDefaults.standard.set(difficulty, forKey: "sgs_difficulty") }
    }
    /// #19 hardcore night races (darker, ×1.5 reward; pink-slips exempt). Default ON.
    @Published var hardcoreNight: Bool = UserDefaults.standard.object(forKey: "sgs_hardcore") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hardcoreNight, forKey: "sgs_hardcore") }
    }
    /// #68 inventory filter: 0 = All, else tier 1-4.
    @Published var invFilter: Int = UserDefaults.standard.integer(forKey: "sgs_inv_filter") {
        didSet { UserDefaults.standard.set(invFilter, forKey: "sgs_inv_filter") }
    }
    /// #68 inventory sort: "tier" (desc) | "type" (A→Z, tier desc tiebreak).
    @Published var invSort: String = UserDefaults.standard.string(forKey: "sgs_inv_sort") ?? "tier" {
        didSet { UserDefaults.standard.set(invSort, forKey: "sgs_inv_sort") }
    }

    struct DiffMods { let susp: Double, heat: Double, pay: Double, green: Double }
    static let diffTable: [String: DiffMods] = [
        "chill":     DiffMods(susp: 0.6, heat: 0.5, pay: 1.2,  green: 1.3),
        "normal":    DiffMods(susp: 1,   heat: 1,   pay: 1,    green: 1),
        "cutthroat": DiffMods(susp: 1.4, heat: 1.5, pay: 0.85, green: 0.75),
    ]
    var diffMods: DiffMods { GameState.diffTable[difficulty] ?? GameState.diffTable["normal"]! }

    // MARK: constants (exact match with web data.js)

    /// App version from Info.plist (#80 What's-New, #79 credits).
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static let tierNames = ["", "Stock", "Sport", "Pro", "Elite"]
    static let tierColors: [Int] = [0, 0x9ca3af, 0x3b82f6, 0xa855f7, 0xf59e0b]
    static let chassisNames = ["", "Rust Bucket", "Street Frame", "Sport Chassis", "Pro Tub"]
    static let partLabels: [String: String] = [
        "engine": "Engine", "turbo": "Turbo", "exhaust": "Exhaust",
        "tires": "Tires", "suspension": "Suspension", "bodykit": "Body Kit",
    ]
    static let partTypes = ["engine", "turbo", "exhaust", "tires", "suspension", "bodykit"]
    static let partIcons: [String: String] = [
        "engine": "⚙️", "turbo": "🌀", "exhaust": "💨",
        "tires": "🛞", "suspension": "🔩", "bodykit": "🎨",
    ]

    struct Friend {
        let name: String
        let tag: String
        let desc: String
        let color: Int
        var bio = ""
        var bestFor = ""
    }
    static let friends: [Friend] = [
        Friend(name: "Rex",  tag: "Smooth Talker", desc: "+30% customer payments",      color: 0xef4444,
               bio: "Once sold a snowmobile to a penguin. Twice. The penguin still writes him thank-you cards.",
               bestFor: "players who fix more than they filch"),
        Friend(name: "Mia",  tag: "Quick Hands",   desc: "Suspicion gains reduced 25%", color: 0x22c55e,
               bio: "Can pocket a carburetor mid-handshake. Her hands have their own alibi and lawyer on retainer.",
               bestFor: "habitual five-finger discounters"),
        Friend(name: "Dex",  tag: "Parts Guru",    desc: "+$25 per Fix",                color: 0x3b82f6,
               bio: "Speaks fluent torque wrench. Once rebuilt a gearbox with a butter knife and pure spite.",
               bestFor: "fix-first grinders stacking honest cash"),
        Friend(name: "Zara", tag: "Wheel Dealer",  desc: "+25% part sell prices",       color: 0xf59e0b,
               bio: "Knows a buyer for everything. EVERYTHING. Do not ask how the stock moves that fast.",
               bestFor: "market-watchers flipping hot parts"),
    ]

    struct Rival {
        let name: String
        let time: Double
        let prizeType: String // part type won on a pink-slip victory
        let prizeTier: Int
        let purse: Int        // cash won on a pink-slip victory
    }
    /// Leaderboard order (fastest first). The pink-slip ladder climbs it from
    /// the back: ladder position 0 = Granny Shift … 3 = Vex, 4 = champion.
    static let rivals: [Rival] = [
        Rival(name: "Vex",          time: 18.5, prizeType: "engine",  prizeTier: 4, purse: 1000),
        Rival(name: "Torque Queen", time: 21.5, prizeType: "turbo",   prizeTier: 3, purse: 500),
        Rival(name: "Lugnut",       time: 25.5, prizeType: "exhaust", prizeTier: 3, purse: 300),
        Rival(name: "Granny Shift", time: 31.0, prizeType: "tires",   prizeTier: 2, purse: 150),
    ]
    /// Rival at pink-slip ladder position `pos` (0–3); nil for the champion (4).
    static func ladderRival(_ pos: Int) -> Rival? {
        guard pos >= 0, pos < rivals.count else { return nil }
        return rivals[rivals.count - 1 - pos]
    }

    // MARK: race tracks (web TRACKS — control points drive Catmull-Rom centerlines)

    struct RaceTrack {
        let id: String
        let name: String
        let feel: String
        let par: Double
        let barrierEvery: Int
        let treeCount: Int
        let points: [SIMD2<Double>]
    }
    static let tracks: [RaceTrack] = [
        RaceTrack(id: "classic", name: "Meadow Loop", feel: "long and flowing", par: 22,
                  barrierEvery: 6, treeCount: 64, points: [
                    [0, -128], [60, -123], [111, -94], [132, -43], [119, 9],
                    [128, 60], [94, 102], [43, 128], [-9, 119], [-68, 128],
                    [-119, 94], [-132, 34], [-119, -26], [-77, -68], [-34, -102],
                  ]),
        RaceTrack(id: "ridge", name: "Figure-8 Ridge", feel: "short and tight", par: 16,
                  barrierEvery: 4, treeCount: 90, points: [
                    // peanut-8: rounded waist U-turns at x≈±26 keep the 16-wide road
                    // clear of itself (~71% of classic's length)
                    [0, -76], [38, -72], [66, -44], [60, -20], [34, -14],
                    [26, -6], [26, 4], [34, 10], [60, 16], [66, 42], [38, 76], [0, 78],
                    [-38, 76], [-66, 42], [-60, 18], [-34, 12],
                    [-26, 4], [-26, -4], [-34, -10], [-60, -16], [-66, -48], [-38, -72],
                  ]),
    ]

    // MARK: ids

    private var uidCounter = 1
    private func uid() -> String {
        uidCounter += 1
        return "id\(uidCounter)_\(Int.random(in: 0..<1_000_000))"
    }

    // MARK: perks (chosen character OR hired crew)

    var payMult: Double  { characterIndex == 0 || crew.contains(0) ? 1.30 : 1 }
    var suspMult: Double { characterIndex == 1 || crew.contains(1) ? 0.75 : 1 }
    var fixBonus: Int    { characterIndex == 2 || crew.contains(2) ? 25 : 0 }
    var sellMult: Double { characterIndex == 3 || crew.contains(3) ? 1.25 : 1 }

    /// One-time hire prices per friend index (Rex 800 / Mia 800 / Dex 2000 / Zara 5000).
    static let crewPrices = [800, 800, 2000, 5000]

    @discardableResult
    func hireCrew(_ i: Int) -> Bool {
        guard GameState.friends.indices.contains(i), i != characterIndex, !crew.contains(i) else { return false }
        let price = GameState.crewPrices[i]
        guard cash >= price else { return false }
        cash -= price
        crew.append(i)
        checkAchievements(.crew) // #73 Team Player
        save()
        return true
    }

    // MARK: economy

    /// Parts Catalog prices (Build bay): buy new parts straight to inventory.
    static let catalogPrices: [Int: Int] = [2: 160, 3: 420, 4: 950]

    func chassisCost(_ L: Int) -> Int? {
        let costs = [1: 250, 2: 500, 3: 900]
        return costs[L]
    }

    /// The fence: deterministic daily demand per part type in [0.6, 1.6]
    /// (FNV-1a hash of type+day — same for everyone, re-rolls daily).
    func demand(_ type: String, day: Int) -> Double {
        var h: UInt64 = 1469598103934665603
        for b in (type + "#\(day)").utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return 0.6 + Double(h % 1000) / 1000
    }

    /// Sell price: 60/tier × today's demand × sell perk. Parts stolen TODAY
    /// are hot — selling them adds +5 heat (handled at the sale site).
    func fencePrice(_ part: Part) -> Int {
        Int((Double(60 * part.tier) * demand(part.type, day: day) * sellMult).rounded())
    }

    // MARK: contracts board

    /// Contract ranks (web CONTRACT_RANKS): reward multiplier + deadline length.
    struct ContractRank { let mult: Double, days: Int, badge: String }
    static let contractRanks: [String: ContractRank] = [
        "standard": ContractRank(mult: 1,   days: 3, badge: "Standard"),
        "rush":     ContractRank(mult: 1.6, days: 1, badge: "Rush"),
        "premium":  ContractRank(mult: 1.5, days: 4, badge: "Premium"),
    ]

    /// Every day advance: expire past-deadline contracts; offer a new one every
    /// 3rd day when none is active (60/20/20 rank roll).
    func advanceDay() {
        day += 1
        if let c = contract, day > c.deadline { contract = nil }
        if day % 3 == 0, contract == nil {
            let rr = Double.random(in: 0..<100)
            let rank = rr < 60 ? "standard" : rr < 80 ? "rush" : "premium"
            let r = Double.random(in: 0..<100)
            let minTier = rank == "premium" ? (r < 70 ? 3 : 4)
                                           : (r < 50 ? 2 : r < 85 ? 3 : 4)
            let rk = GameState.contractRanks[rank]!
            contract = Contract(type: GameState.partTypes.randomElement()!, minTier: minTier,
                                deadline: day + rk.days,
                                reward: Int((60.0 * Double(minTier) * 2.2 * rk.mult).rounded()),
                                rank: rank)
        }
    }

    /// Consume the lowest-tier matching part in inventory; pay the reward.
    /// Returns the reward on success.
    @discardableResult
    func fulfillContract() -> Int? {
        guard let c = contract else { return nil }
        let match = inventory.filter { $0.type == c.type && $0.tier >= c.minTier }
            .sorted { $0.tier < $1.tier }.first
        guard let part = match, let idx = inventory.firstIndex(where: { $0.id == part.id }) else { return nil }
        inventory.remove(at: idx)
        cash += c.reward
        stats.contractsDone += 1 // #74
        addEarnings(c.reward)    // #74 lifetime earnings
        contract = nil
        checkAchievements(.contract) // #73 Paperwork / Union Rep
        save()
        return c.reward
    }

    func computeStats() -> Stats {
        let L = car.chassis
        var speed = 18 + 9 * L
        var accel = 16 + 9 * L
        var handling = 18 + 8 * L
        if let p = car.parts.engine     { speed += 11 * p.tier; accel += 9 * p.tier }
        if let p = car.parts.turbo      { speed += 9 * p.tier; accel += 7 * p.tier }
        if let p = car.parts.exhaust    { accel += 8 * p.tier; speed += 5 * p.tier }
        if let p = car.parts.tires      { handling += 11 * p.tier; accel += 4 * p.tier }
        if let p = car.parts.suspension { handling += 13 * p.tier }
        if let p = car.parts.bodykit    { handling += 9 * p.tier; speed += 4 * p.tier }
        let clamp = { min(100, max(0, $0)) }
        return Stats(speed: clamp(speed), accel: clamp(accel), handling: clamp(handling))
    }

    // MARK: customer generation

    private static let firstNames = ["Sam","Pat","Jo","Alex","Rita","Gus","Lena","Marco","Ivy","Otto",
        "Nina","Pete","Sana","Theo","Wendy","Kai","Rosa","Felix","June","Omar","Bea","Hank","Lulu","Ezra"]
    private static let lastInitials = Array("ABCDEFGHJKLMNPRSTW")
    private static let pastelColors = [0xf8b4b4, 0xfde68a, 0xa7f3d0, 0xbfdbfe, 0xddd6fe,
        0xfbcfe8, 0x99e9f2, 0xfed7aa, 0xd9f99d, 0xc7d2fe]

    // tier weights: 1:45% 2:30% 3:17% 4:8% (BigSpenders: 1:25% 2:35% 3:25% 4:15%)
    private func weightedTier(_ archetype: String) -> Int {
        let r = Double.random(in: 0..<100)
        if archetype == "bigspender" {
            if r < 25 { return 1 }
            if r < 60 { return 2 }
            if r < 85 { return 3 }
            return 4
        }
        if r < 45 { return 1 }
        if r < 75 { return 2 }
        if r < 92 { return 3 }
        return 4
    }

    /// Debug launch arg `-arch <type>` pins every generated customer to an archetype.
    var forcedArchetype: String? = nil
    /// Debug launch arg `-golden` pins every generated customer golden (screenshots).
    var forcedGolden = false

    /// Archetype roll: Regular 55% / Rushed 15% / Skeptic 15% / BigSpender 15%.
    private func rollArchetype() -> String {
        if let forced = forcedArchetype { return forced }
        let r = Double.random(in: 0..<100)
        if r < 55 { return "regular" }
        if r < 70 { return "rushed" }
        if r < 85 { return "skeptic" }
        return "bigspender"
    }

    /// Payment multiplier for the archetype. Rushed pays ×1.5 only when the job
    /// finished inside the 45s window (`onTime`); Skeptic ×1.25; BigSpender ×1.5.
    func archPayMult(_ archetype: String, onTime: Bool) -> Double {
        switch archetype {
        case "rushed":     return onTime ? 1.5 : 1
        case "skeptic":    return 1.25
        case "bigspender": return 1.5
        default:           return 1
        }
    }

    /// Suspicion multiplier for the archetype (Skeptic ×1.5, stacks with Mia).
    func archSuspMult(_ archetype: String) -> Double {
        archetype == "skeptic" ? 1.5 : 1
    }

    /// Job-panel badge emoji (Regular gets none).
    static func archBadge(_ archetype: String) -> String {
        switch archetype {
        case "skeptic":    return "🧐"
        case "bigspender": return "💰"
        default:           return ""
        }
    }

    func generateCustomer() -> Customer {
        // body style: sedan 50% / hatch 25% / truck 25%; trucks lean Big Spender
        let sr = Double.random(in: 0..<100)
        let bodyStyle = sr < 50 ? "sedan" : sr < 75 ? "hatch" : "truck"
        var archetype = rollArchetype()
        if bodyStyle == "truck", Double.random(in: 0..<1) < 0.5 { archetype = "bigspender" }
        if let forced = forcedArchetype { archetype = forced }
        // golden customer: 3% — all parts tier ≥3, pays ×3
        let golden = forcedGolden || Double.random(in: 0..<1) < 0.03
        var parts: [CustomerPart]
        repeat {
            parts = GameState.partTypes.map { type in
                CustomerPart(id: uid(), type: type,
                             tier: golden ? max(3, weightedTier(archetype)) : weightedTier(archetype),
                             needsService: Double.random(in: 0..<1) < 0.6)
            }
        } while !parts.contains { $0.needsService } // at least one part must need service

        // elite pity: 25 customers without a tier-4 sighting forces one tier-4 part
        if elitePity >= 25 {
            parts[Int.random(in: 0..<parts.count)].tier = 4
            elitePity = 0
        } else if parts.contains(where: { $0.tier == 4 }) {
            elitePity = 0
        } else {
            elitePity += 1
        }

        let name = "\(GameState.firstNames.randomElement()!) \(GameState.lastInitials.randomElement()!)."
        return Customer(id: uid(), name: name,
                        color: golden ? 0xf5c542 : GameState.pastelColors.randomElement()!,
                        parts: parts, archetype: archetype, bodyStyle: bodyStyle, golden: golden)
    }

    func makePart(_ type: String, _ tier: Int) -> Part {
        Part(id: uid(), type: type, tier: tier)
    }

    // MARK: lifecycle

    func newGame(_ name: String, _ charIndex: Int) {
        // trim first, then cap at 14 chars (cap is applied here on commit, not
        // per keystroke, so IME composition is never mangled)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        playerName = trimmed.isEmpty ? "Boss" : String(trimmed.prefix(14))
        characterIndex = charIndex
        cash = 200
        day = 1
        inventory = []
        car = CarBuild()
        bestLap = nil
        carValue = 0
        customersServed = 0
        suspicion = 0
        heat = 0
        raceCount = 0
        ladder = 0
        legend = false
        heatHintShown = false
        copHintShown = false
        contract = nil
        crew = []
        tutorialSeen = false
        elitePity = 0
        bestLaps = [:]
        cleanStreak = 0
        achievements = []
        stats = LifetimeStats()
        hof = []
        daily = DailyBests()
        lastSeenVersion = Self.appVersion // first-ever players never see What's-New
        save()
    }

    // MARK: persistence (UserDefaults, JSON, key 'sgs_save')

    private let saveKey = "sgs_save"
    private let prevSaveKey = "sgs_save_prev"

    /// Set by AppState; fires at most once per session when persistence fails.
    var onSaveFailure: (() -> Void)?
    private var saveFailureToastShown = false

    func save() {
        let data = SaveData(
            playerName: playerName, characterIndex: characterIndex, cash: cash, day: day,
            inventory: inventory, car: car, bestLap: bestLap, carValue: carValue,
            customersServed: customersServed, suspicion: suspicion, heat: heat,
            raceCount: raceCount, ladder: ladder, legend: legend,
            heatHintShown: heatHintShown, copHintShown: copHintShown,
            contract: contract, crew: crew, tutorialSeen: tutorialSeen,
            elitePity: elitePity, bestLaps: bestLaps,
            savedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            cleanStreak: cleanStreak, achievements: achievements, stats: stats,
            hof: hof, daily: daily, lastSeenVersion: lastSeenVersion)
        // Fail silent, but warn once — a broken save must never crash the game.
        do {
            let json = try JSONEncoder().encode(data)
            // keep the previous blob before each overwrite (web #88)
            if let prev = UserDefaults.standard.data(forKey: saveKey) {
                UserDefaults.standard.set(prev, forKey: prevSaveKey)
            }
            UserDefaults.standard.set(json, forKey: saveKey)
            CloudSync.shared.push(json: json) // #52 iCloud (no-op unless enabled)
        } catch {
            if !saveFailureToastShown {
                saveFailureToastShown = true
                onSaveFailure?()
            }
        }
    }

    func hasBackup() -> Bool {
        UserDefaults.standard.data(forKey: prevSaveKey) != nil
    }

    /// Restore the pre-overwrite backup blob into the active slot (Settings).
    @discardableResult
    func restorePrevious() -> Bool {
        guard let json = UserDefaults.standard.data(forKey: prevSaveKey),
              let raw = try? JSONDecoder().decode(RawSave.self, from: json) else { return false }
        applyLoaded(raw)
        save()
        return true
    }

    struct SaveExport: Codable {
        var app: String
        var saveVersion: Int
        var exportedAt: String
        var data: SaveData
    }

    /// JSON export for the share sheet (web exportSave()).
    func exportSaveJSON() -> String {
        let data = SaveData(
            playerName: playerName, characterIndex: characterIndex, cash: cash, day: day,
            inventory: inventory, car: car, bestLap: bestLap, carValue: carValue,
            customersServed: customersServed, suspicion: suspicion, heat: heat,
            raceCount: raceCount, ladder: ladder, legend: legend,
            heatHintShown: heatHintShown, copHintShown: copHintShown,
            contract: contract, crew: crew, tutorialSeen: tutorialSeen,
            elitePity: elitePity, bestLaps: bestLaps,
            savedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
            cleanStreak: cleanStreak, achievements: achievements, stats: stats,
            hof: hof, daily: daily, lastSeenVersion: lastSeenVersion)
        let payload = SaveExport(app: "shady-garage-speed", saveVersion: 2,
                                 exportedAt: ISO8601DateFormatter().string(from: Date()), data: data)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let json = try? encoder.encode(payload) else { return "{}" }
        return String(decoding: json, as: UTF8.self)
    }

    /// Wipe save + backup and reset in-memory state (Settings, double-confirmed).
    func resetEverything() {
        UserDefaults.standard.removeObject(forKey: saveKey)
        UserDefaults.standard.removeObject(forKey: prevSaveKey)
        applyLoaded(RawSave()) // all-nil backfill = fresh defaults
    }

    func hasSave() -> Bool {
        UserDefaults.standard.data(forKey: saveKey) != nil
    }

    @discardableResult
    func load() -> Bool {
        guard let json = UserDefaults.standard.data(forKey: saveKey),
              let raw = try? JSONDecoder().decode(RawSave.self, from: json) else { return false }
        applyLoaded(raw)
        // #70 offline heat decay: −2 heat per hour away, max −20, never below 0.
        // AppState toasts "Things cooled off…" when offlineCool ≥ 10.
        offlineCool = 0
        if let ms = raw.savedAtMs, ms > 0, heat > 0 {
            let hours = max(0, (Date().timeIntervalSince1970 * 1000 - Double(ms)) / 3_600_000)
            offlineCool = min(20, Int(hours * 2), heat)
            heat = max(0, heat - offlineCool)
        }
        return true
    }

    // Merge a possibly old-shaped save over defaults (backfill like web applyLoaded).
    func applyLoaded(_ raw: RawSave) {
        playerName = raw.playerName ?? "Boss"
        characterIndex = min(3, max(0, raw.characterIndex ?? 0))
        cash = max(0, raw.cash ?? 200)
        day = max(1, raw.day ?? 1)
        inventory = raw.inventory ?? []
        var build = CarBuild()
        build.chassis = min(4, max(1, raw.car?.chassis ?? 1))
        build.parts = raw.car?.parts ?? CarParts()
        car = build
        bestLap = raw.bestLap ?? nil
        carValue = raw.carValue ?? 0
        customersServed = raw.customersServed ?? 0
        // Suspicion is per-customer and must NOT survive a relaunch onto a fresh
        // customer — always start at 0 (the field stays in the save for compat).
        suspicion = 0
        heat = min(100, max(0, raw.heat ?? 0))
        raceCount = max(0, raw.raceCount ?? 0)
        ladder = min(4, max(0, raw.ladder ?? 0))
        legend = (raw.legend ?? false) || ladder >= 4
        heatHintShown = raw.heatHintShown ?? false
        copHintShown = raw.copHintShown ?? false
        contract = raw.contract
        crew = raw.crew ?? []
        tutorialSeen = raw.tutorialSeen ?? false
        elitePity = max(0, raw.elitePity ?? 0)
        bestLaps = raw.bestLaps ?? [:]
        cleanStreak = max(0, raw.cleanStreak ?? 0)
        achievements = (raw.achievements ?? []).filter { Achievements.byId[$0] != nil }
        stats = raw.stats ?? LifetimeStats()
        hof = Array((raw.hof ?? []).prefix(10))
        daily = raw.daily ?? DailyBests()
        lastSeenVersion = raw.lastSeenVersion ?? ""
        // migration: the legacy scalar bestLap belongs to the classic track
        if bestLaps["classic"] == nil, let legacy = bestLap {
            bestLaps["classic"] = legacy
        }
    }
}

// MARK: - Save shapes

struct SaveData: Codable {
    var playerName: String
    var characterIndex: Int
    var cash: Int
    var day: Int
    var inventory: [Part]
    var car: CarBuild
    var bestLap: Double?
    var carValue: Int
    var customersServed: Int
    var suspicion: Int
    var heat: Int
    var raceCount: Int
    var ladder: Int
    var legend: Bool
    var heatHintShown: Bool
    var copHintShown: Bool
    var contract: Contract?
    var crew: [Int]
    var tutorialSeen: Bool
    var elitePity: Int
    var bestLaps: [String: Double]
    /// #52 iCloud LWW merge clock (ms since epoch; 0 in legacy saves).
    var savedAtMs: Int64
    /// #15 clean-job streak (0 in legacy saves).
    var cleanStreak: Int
    var achievements: [String]      // #73
    var stats: LifetimeStats        // #74
    var hof: [HofEntry]             // #75
    var daily: DailyBests           // #72
    var lastSeenVersion: String     // #80
}

// All-optional shape so older saves missing new fields still decode (migration).
struct RawSave: Codable {
    var playerName: String?
    var characterIndex: Int?
    var cash: Int?
    var day: Int?
    var inventory: [Part]?
    var car: RawCar?
    var bestLap: Double?
    var carValue: Int?
    var customersServed: Int?
    var suspicion: Int?
    var heat: Int?
    var raceCount: Int?
    var ladder: Int?
    var legend: Bool?
    var heatHintShown: Bool?
    var copHintShown: Bool?
    var contract: Contract?
    var crew: [Int]?
    var tutorialSeen: Bool?
    var elitePity: Int?
    var bestLaps: [String: Double]?
    /// #52 merge clock; absent (nil → 0) in legacy saves.
    var savedAtMs: Int64?
    /// #15 clean-job streak; absent (nil → 0) in legacy saves.
    var cleanStreak: Int?
    var achievements: [String]?
    var stats: LifetimeStats?
    var hof: [HofEntry]?
    var daily: DailyBests?
    var lastSeenVersion: String?
}

struct RawCar: Codable {
    var chassis: Int?
    var parts: CarParts?
}
