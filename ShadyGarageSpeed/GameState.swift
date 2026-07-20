// GameState.swift — port of data.js: state, tiers, friends/perks, customers, persistence.
import Foundation
import Combine

// MARK: - Models

struct Part: Codable, Equatable, Identifiable {
    var id: String
    var type: String   // engine | turbo | exhaust | tires | suspension | bodykit
    var tier: Int      // 1..4
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

    struct Rival { let name: String; let time: Double }
    static let rivals: [Rival] = [
        Rival(name: "Vex",          time: 18.5),
        Rival(name: "Torque Queen", time: 21.5),
        Rival(name: "Lugnut",       time: 25.5),
        Rival(name: "Granny Shift", time: 31.0),
    ]

    // MARK: ids

    private var uidCounter = 1
    private func uid() -> String {
        uidCounter += 1
        return "id\(uidCounter)_\(Int.random(in: 0..<1_000_000))"
    }

    // MARK: perks

    var payMult: Double  { characterIndex == 0 ? 1.30 : 1 }
    var suspMult: Double { characterIndex == 1 ? 0.75 : 1 }
    var fixBonus: Int    { characterIndex == 2 ? 25 : 0 }
    var sellMult: Double { characterIndex == 3 ? 1.25 : 1 }

    // MARK: economy

    /// Parts Catalog prices (Build bay): buy new parts straight to inventory.
    static let catalogPrices: [Int: Int] = [2: 160, 3: 420, 4: 950]

    func chassisCost(_ L: Int) -> Int? {
        let costs = [1: 250, 2: 500, 3: 900]
        return costs[L]
    }
    func partSellPrice(_ tier: Int) -> Int { 60 * tier }

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

    // tier weights: 1:45% 2:30% 3:17% 4:8%
    private func weightedTier() -> Int {
        let r = Double.random(in: 0..<100)
        if r < 45 { return 1 }
        if r < 75 { return 2 }
        if r < 92 { return 3 }
        return 4
    }

    func generateCustomer() -> Customer {
        var parts: [CustomerPart]
        repeat {
            parts = GameState.partTypes.map { type in
                CustomerPart(id: uid(), type: type, tier: weightedTier(),
                             needsService: Double.random(in: 0..<1) < 0.6)
            }
        } while !parts.contains { $0.needsService } // at least one part must need service
        let name = "\(GameState.firstNames.randomElement()!) \(GameState.lastInitials.randomElement()!)."
        return Customer(id: uid(), name: name,
                        color: GameState.pastelColors.randomElement()!, parts: parts)
    }

    func makePart(_ type: String, _ tier: Int) -> Part {
        Part(id: uid(), type: type, tier: tier)
    }

    // MARK: lifecycle

    func newGame(_ name: String, _ charIndex: Int) {
        playerName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Boss" : String(name.prefix(14))
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
            customersServed: customersServed, suspicion: suspicion, heat: heat, raceCount: raceCount)
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
}

struct RawCar: Codable {
    var chassis: Int?
    var parts: CarParts?
}
