// MetaSystems.swift — social/meta content ported verbatim from the web:
// #73 achievement table + checker (js/data.js), #74 lifetime stats, #75 HoF ring,
// #72 daily-rival RNG (mulberry32/hashStr — boards must match the web),
// #76 friend bios, #80 CHANGELOG (js/version.js), #71 share-card layout (js/ui.js).
import UIKit

// MARK: #73 achievements (table order = gallery order)

struct AchievementDef {
    let icon: String
    let name: String
    let desc: String
}

enum Achievements {
    static let table: [(id: String, def: AchievementDef)] = [
        ("first_fix",      AchievementDef(icon: "🔧", name: "First Wrench",        desc: "Fix your first part.")),
        ("first_steal",    AchievementDef(icon: "🕵️", name: "Five-Finger Discount", desc: "Steal your first part.")),
        ("first_rage",     AchievementDef(icon: "💢", name: "Busted",              desc: "Have a customer storm off furious.")),
        ("cust_10",        AchievementDef(icon: "🚗", name: "Regulars",            desc: "Serve 10 customers.")),
        ("cust_50",        AchievementDef(icon: "🏭", name: "Assembly Line",       desc: "Serve 50 customers.")),
        ("first_elite",    AchievementDef(icon: "💎", name: "Shiny",               desc: "Get your first Elite part.")),
        ("full_elite",     AchievementDef(icon: "👑", name: "Full Dress",          desc: "Run a full Elite build — every slot Elite.")),
        ("first_pinkslip", AchievementDef(icon: "🏁", name: "Pink Slippery",       desc: "Win your first pink-slip race.")),
        ("street_legend",  AchievementDef(icon: "🏆", name: "Street Legend",       desc: "Beat Vex and take the crown.")),
        ("sub20_classic",  AchievementDef(icon: "⏱️", name: "Meadow Rocket",       desc: "Lap Meadow Loop under 20s.")),
        ("sub15_ridge",    AchievementDef(icon: "🚀", name: "Ridge Runner",        desc: "Lap Figure-8 Ridge under 15s.")),
        ("earn_1k",        AchievementDef(icon: "💵", name: "First Grand",         desc: "Earn $1,000 lifetime.")),
        ("earn_10k",       AchievementDef(icon: "🤑", name: "Mogul",               desc: "Earn $10,000 lifetime.")),
        ("clean_5",        AchievementDef(icon: "🔥", name: "Squeaky Clean",       desc: "Reach a 5-job clean streak.")),
        ("combo_3",        AchievementDef(icon: "🎯", name: "Surgeon",             desc: "Land 3 green swaps in a row.")),
        ("first_contract", AchievementDef(icon: "📋", name: "Paperwork",           desc: "Fulfill your first contract.")),
        ("contracts_5",    AchievementDef(icon: "🗂️", name: "Union Rep",           desc: "Fulfill 5 contracts.")),
        ("crew_hire",      AchievementDef(icon: "👥", name: "Team Player",         desc: "Hire a crew member.")),
        ("max_chassis",    AchievementDef(icon: "🏎️", name: "Pro Tub",             desc: "Upgrade to the max chassis.")),
        ("raid_survive",   AchievementDef(icon: "🚔", name: "Still Standing",      desc: "Survive a police raid.")),
    ]

    static let byId = Dictionary(uniqueKeysWithValues: table.map { ($0.id, $0.def) })
}

/// One evaluation entry point — mirrors web checkAchievements(event, payload).
enum AchEvent {
    case fix, steal, rage, customer, elitePart, build, pinkslip, legend
    case cash, cleanStreak, contract, crew, raid
    case lap(trackId: String, lap: Double)
    case combo(Int)
}

// MARK: #74 lifetime stats

struct LifetimeStats: Codable {
    var fixes = 0, steals = 0, rages = 0, raids = 0
    var earnings = 0, races = 0, contractsDone = 0, playtimeSec = 0
    var archSeen: [String: Int] = ["regular": 0, "rushed": 0, "skeptic": 0, "bigspender": 0]
}

// MARK: #75 Hall of Fame ring (last 10 finished runs)

struct HofEntry: Codable, Identifiable {
    var id = UUID()
    var date: Double   // ms since epoch
    var track: String  // track id (+R when reversed)
    var lap: Double
    var place: Int
    var speed: Int
    var accel: Int
    var handling: Int
    var challengeName: String?
    var challengeWin: Bool?
    var legend: Bool
}

// MARK: #72 daily best (resets at midnight local)

struct DailyBests: Codable {
    var date: String = ""
    var bests: [String: Double] = [:]
}

// MARK: deterministic RNG (exact port — same boards as the web)

func mulberry32(_ seed: UInt32) -> () -> Double {
    var a = seed
    return {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

func hashStr(_ s: String) -> UInt32 {
    var h: UInt32 = 2166136261 // FNV-1a over UTF-16 code units (JS charCodeAt)
    for u in s.utf16 { h = (h ^ UInt32(u)) &* 16777619 }
    return h
}

func todayKey(_ d: Date = Date()) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
}

/// #72 five synthetic rivals, deterministic per date, par-scaled, sorted.
func dailyRivals(par: Double, for d: Date = Date()) -> [(name: String, time: Double)] {
    let r = mulberry32(hashStr("daily:" + todayKey(d)))
    var times: [Double] = []
    for _ in 0..<5 { times.append((par * (0.85 + r() * 0.45) * 100).rounded() / 100) }
    return times.sorted().enumerated().map { ("D-\($0.offset + 1)", $0.element) }
}

// MARK: #80 CHANGELOG (js/version.js, verbatim)

enum Changelog {
    static let bullets: [String: [String]] = [
        "1.0.0": [
            "Two race tracks (+ ⇄ reversed variants) with per-track best laps",
            "Golden customers, elite pity timer & tiered contracts",
            "Achievements, lifetime stats, Hall of Fame & daily rival board",
            "Procedural music, rain/fog weather & a whole lot of juice",
            "Clean streaks, green combos & warier late-game customers",
        ],
        "default": ["Quality-of-life polish and bug fixes."],
    ]

    /// Lookup key: plist "1.0" normalizes to the web's "1.0.0" entry.
    static func bullets(for version: String) -> [String] {
        let key = version.components(separatedBy: ".").count == 2 ? version + ".0" : version
        return bullets[key] ?? bullets["default"]!
    }
}

// MARK: #71 share card (1200×630, mirrors js/ui.js renderShareCard)

enum ShareCard {
    /// 5×7 voxel glyphs for the badge monogram (web VOX).
    private static let vox: [Character: [String]] = [
        "S": ["01110", "10001", "10000", "01110", "00001", "10001", "01110"],
        "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    ]

    private static func drawVox(_ ch: Character, x: CGFloat, y: CGFloat, px: CGFloat,
                                color: UIColor, in ctx: CGContext) {
        ctx.setFillColor(color.cgColor)
        vox[ch]?.enumerated().forEach { ry, row in
            row.enumerated().forEach { rx, bit in
                if bit == "1" {
                    ctx.fill(CGRect(x: x + CGFloat(rx) * px, y: y + CGFloat(ry) * px,
                                    width: px - 1, height: px - 1))
                }
            }
        }
    }

    private static func drawCentered(_ text: String, y: CGFloat, font: UIFont,
                                     color: UIColor, in ctx: CGContext) {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                    .paragraphStyle: p]
        text.draw(with: CGRect(x: 0, y: y - font.ascender, width: 1200,
                               height: font.ascender + font.descender),
                  options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
    }

    /// lap: seconds; trackName: display name (+ " (reversed)"); stats: car build;
    /// place/placeOf vs rivals (nil when a pink-slip ran); challenge: win/lose line.
    static func render(lap: Double, trackName: String, speed: Int, accel: Int, handling: Int,
                       place: Int, placeOf: Int, challenge: (name: String, win: Bool)?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // exactly 1200×630 px (web OG-card size), not device scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 630), format: format)
        return renderer.image { r in
            let ctx = r.cgContext
            // dark bg + orange footer strip (OG card style)
            UIColor(rgb: 0x0b0e14).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
            UIColor(rgb: 0xff5d3b).setFill()
            ctx.fill(CGRect(x: 0, y: 612, width: 1200, height: 18))
            // voxel SG badge (rounded-rect outline, white S + orange G)
            UIColor(rgb: 0xff5d3b).setStroke()
            ctx.setLineWidth(10)
            UIBezierPath(roundedRect: CGRect(x: 470, y: 46, width: 260, height: 190),
                         cornerRadius: 26).stroke()
            drawVox("S", x: 512, y: 82, px: 20, color: UIColor(rgb: 0xf8fafc), in: ctx)
            drawVox("G", x: 626, y: 82, px: 20, color: UIColor(rgb: 0xff5d3b), in: ctx)
            // lap time + track + stats + placement + date footer
            drawCentered(RaceScene.fmtTime(lap), y: 350,
                         font: .monospacedSystemFont(ofSize: 96, weight: .black),
                         color: UIColor(rgb: 0xf8fafc), in: ctx)
            drawCentered(trackName.uppercased(), y: 408,
                         font: .systemFont(ofSize: 40, weight: .heavy),
                         color: UIColor(rgb: 0xff5d3b), in: ctx)
            drawCentered("SPD \(speed) · ACC \(accel) · HDL \(handling)", y: 462,
                         font: .systemFont(ofSize: 30, weight: .semibold),
                         color: UIColor(rgb: 0x94a3b8), in: ctx)
            let line = challenge.map { $0.win ? "🏆 Beat \($0.name)!" : "Lost to \($0.name)" }
                ?? "Placed #\(place) of \(placeOf) vs rivals"
            drawCentered(line, y: 522, font: .systemFont(ofSize: 34, weight: .bold),
                         color: UIColor(rgb: 0xf8fafc), in: ctx)
            drawCentered("SHADY GARAGE & SPEED · \(todayKey())", y: 576,
                         font: .systemFont(ofSize: 24, weight: .medium),
                         color: UIColor(rgb: 0x64748b), in: ctx)
        }
    }
}
