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

/// Contracts board: a typed part order with a deadline (day) and cash reward.
struct Contract: Codable, Equatable {
    var type: String
    var minTier: Int
    var deadline: Int
    var reward: Int
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

    // MARK: constants (exact match with web data.js)

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
    }
    static let friends: [Friend] = [
        Friend(name: "Rex",  tag: "Smooth Talker", desc: "+30% customer payments",      color: 0xef4444),
        Friend(name: "Mia",  tag: "Quick Hands",   desc: "Suspicion gains reduced 25%", color: 0x22c55e),
        Friend(name: "Dex",  tag: "Parts Guru",    desc: "+$25 per Fix",                color: 0x3b82f6),
        Friend(name: "Zara", tag: "Wheel Dealer",  desc: "+25% part sell prices",       color: 0xf59e0b),
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

    /// Every day advance: expire past-deadline contracts; offer a new one every
    /// 3rd day when none is active (minTier 2–4, deadline day+3, reward 60·tier·2.2).
    func advanceDay() {
        day += 1
        if let c = contract, day > c.deadline { contract = nil }
        if day % 3 == 0, contract == nil {
            let type = GameState.partTypes.randomElement()!
            let minTier = Int.random(in: 2...4)
            contract = Contract(type: type, minTier: minTier, deadline: day + 3,
                                reward: Int((60.0 * Double(minTier) * 2.2).rounded()))
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
        contract = nil
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
        let archetype = rollArchetype()
        var parts: [CustomerPart]
        repeat {
            parts = GameState.partTypes.map { type in
                CustomerPart(id: uid(), type: type, tier: weightedTier(archetype),
                             needsService: Double.random(in: 0..<1) < 0.6)
            }
        } while !parts.contains { $0.needsService } // at least one part must need service
        let name = "\(GameState.firstNames.randomElement()!) \(GameState.lastInitials.randomElement()!)."
        return Customer(id: uid(), name: name,
                        color: GameState.pastelColors.randomElement()!, parts: parts,
                        archetype: archetype)
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
        save()
    }

    // MARK: persistence (UserDefaults, JSON, key 'sgs_save')

    private let saveKey = "sgs_save"

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
            contract: contract, crew: crew)
        // Fail silent, but warn once — a broken save must never crash the game.
        do {
            let json = try JSONEncoder().encode(data)
            UserDefaults.standard.set(json, forKey: saveKey)
        } catch {
            if !saveFailureToastShown {
                saveFailureToastShown = true
                onSaveFailure?()
            }
        }
    }

    func hasSave() -> Bool {
        UserDefaults.standard.data(forKey: saveKey) != nil
    }

    @discardableResult
    func load() -> Bool {
        guard let json = UserDefaults.standard.data(forKey: saveKey),
              let raw = try? JSONDecoder().decode(RawSave.self, from: json) else { return false }
        applyLoaded(raw)
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
}

struct RawCar: Codable {
    var chassis: Int?
    var parts: CarParts?
}
