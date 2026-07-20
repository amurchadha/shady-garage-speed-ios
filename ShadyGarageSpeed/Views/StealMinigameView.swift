// StealMinigameView.swift — stealth timing minigame (mirrors #modal-minigame).
// Marker sweeps 0–100% by WALL-CLOCK delta (CACurrentMediaTime), so throttling
// or backgrounding can't change the difficulty; the sweep pauses while the app
// is inactive. Green width & marker speed scale with part tier and heat.
// Colorblind-safe: each zone has a distinct pattern (solid/stripes/grid), the
// green zone carries a center notch, and the marker is a bold triangle.
// prefers-reduced-motion slows the marker to ×0.6.
import SwiftUI
import QuartzCore

struct StealMinigameView: View {
    let title: String
    var tier: Int = 2
    var heat: Int = 0
    let onResolve: (String) -> Void // "green" | "yellow" | "red"

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var g: Double = 30        // green zone left edge, %
    @State private var pos: Double = 0       // marker, %
    @State private var dir: Double = 1
    @State private var flash: String? = nil
    @State private var resolved = false
    @State private var lastTick: CFTimeInterval? = nil

    private let ticker = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    /// Green width: 18 − 3·(tier−1) − heat/25, floored at 6%.
    private var greenW: Double {
        max(6, 18 - 3 * Double(tier - 1) - Double(heat) / 25)
    }

    /// Marker speed: 95 + 20·(tier−1) %/s (×0.6 with reduce-motion).
    private var markerSpeed: Double {
        (95 + 20 * Double(tier - 1)) * (reduceMotion ? 0.6 : 1)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.title3.bold())
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Canvas { ctx, size in
                            drawBar(ctx: ctx, size: size)
                        }
                        if let flash {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(flashColor(flash).opacity(0.55))
                        }
                    }
                }
                .frame(height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
                .onTapGesture { resolve() }
                .accessibilityIdentifier("mg-bar")
                Text("Tap the bar or SWAP when the marker is in the green zone!")
                    .font(.footnote)
                    .foregroundStyle(Color.sgsMuted)
                    .multilineTextAlignment(.center)
                SGSButton(title: "SWAP!", big: true, a11y: "mg-swap") { resolve() }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .background(Color.sgsCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(16)
        }
        .onAppear {
            let gMax = max(13, 100 - greenW - 11)
            g = 12 + Double.random(in: 0..<(gMax - 12))
            pos = Double.random(in: 0..<100)
            dir = Double.random(in: 0..<1) < 0.5 ? 1 : -1
        }
        .onReceive(ticker) { _ in
            // wall-clock deltas: throttled/dropped ticks can't slow the marker,
            // and the sweep pauses cleanly while the app is inactive
            guard !resolved, scenePhase == .active else { lastTick = nil; return }
            let now = CACurrentMediaTime()
            defer { lastTick = now }
            guard let last = lastTick else { return }
            let dt = min(0.1, now - last)
            let bandBefore = zoneBand(pos)
            pos += dir * markerSpeed * dt
            if pos >= 100 { pos = 100; dir = -1 }
            if pos <= 0 { pos = 0; dir = 1 }
            if zoneBand(pos) != bandBefore { Haptics.zoneTick() } // edge-crossing tick
        }
    }

    // MARK: colorblind-safe bar drawing (pattern per zone)

    private func rect(_ x: Double, _ w: Double, in size: CGSize) -> CGRect {
        CGRect(x: size.width * x / 100, y: 0, width: size.width * w / 100, height: size.height)
    }

    private func drawBar(ctx: GraphicsContext, size: CGSize) {
        // red base: grid (cross-hatch)
        let redR = rect(0, 100, in: size)
        ctx.fill(Path(redR), with: .color(Color.sgsBad.opacity(0.30)))
        grid(ctx: ctx, in: redR, color: Color.sgsBad.opacity(0.55))

        // yellow flanks: vertical stripes
        for (x, w) in [(g - 9, 9.0), (g + greenW, 9.0)] where w > 0 {
            let r = rect(x, w, in: size)
            ctx.fill(Path(r), with: .color(Color.sgsWarn.opacity(0.45)))
            stripes(ctx: ctx, in: r, color: Color.sgsWarn.opacity(0.75))
        }

        // green: solid + white center notch
        let gr = rect(g, greenW, in: size)
        ctx.fill(Path(gr), with: .color(Color.sgsGood.opacity(0.85)))
        let cx = gr.midX
        var notch = Path()
        notch.move(to: CGPoint(x: cx - 5, y: 0))
        notch.addLine(to: CGPoint(x: cx + 5, y: 0))
        notch.addLine(to: CGPoint(x: cx, y: 8))
        notch.closeSubpath()
        ctx.fill(notch, with: .color(.white))

        // marker: bold triangle
        let mx = size.width * CGFloat(pos) / 100
        var tri = Path()
        tri.move(to: CGPoint(x: mx, y: size.height / 2 - 9))
        tri.addLine(to: CGPoint(x: mx - 8, y: size.height / 2 + 8))
        tri.addLine(to: CGPoint(x: mx + 8, y: size.height / 2 + 8))
        tri.closeSubpath()
        ctx.fill(tri, with: .color(.white))
        ctx.stroke(tri, with: .color(.black.opacity(0.65)), lineWidth: 1.5)
    }

    private func stripes(ctx: GraphicsContext, in r: CGRect, color: Color) {
        var x = r.minX + 2
        while x < r.maxX {
            var p = Path()
            p.move(to: CGPoint(x: x, y: r.minY))
            p.addLine(to: CGPoint(x: x, y: r.maxY))
            ctx.stroke(p, with: .color(color), lineWidth: 1.5)
            x += 5
        }
    }

    private func grid(ctx: GraphicsContext, in r: CGRect, color: Color) {
        var x = r.minX + 3
        while x < r.maxX {
            var p = Path()
            p.move(to: CGPoint(x: x, y: r.minY))
            p.addLine(to: CGPoint(x: x, y: r.maxY))
            ctx.stroke(p, with: .color(color), lineWidth: 1)
            x += 6
        }
        var y = r.minY + 3
        while y < r.maxY {
            var p = Path()
            p.move(to: CGPoint(x: r.minX, y: y))
            p.addLine(to: CGPoint(x: r.maxX, y: y))
            ctx.stroke(p, with: .color(color), lineWidth: 1)
            y += 6
        }
    }

    /// Which band the marker sits in (left red / left yellow / green / right yellow / right red).
    private func zoneBand(_ p: Double) -> Int {
        if p < g - 9 { return 0 }
        if p < g { return 1 }
        if p <= g + greenW { return 2 }
        if p <= g + greenW + 9 { return 3 }
        return 4
    }

    private func flashColor(_ zone: String) -> Color {
        switch zone {
        case "green": return .sgsGood
        case "yellow": return .sgsWarn
        default: return .sgsBad
        }
    }

    private func resolve() {
        guard !resolved else { return }
        resolved = true
        var zone = "red"
        if pos >= g && pos <= g + greenW {
            zone = "green"
        } else if (pos >= g - 9 && pos < g) || (pos > g + greenW && pos <= g + greenW + 9) {
            zone = "yellow"
        }
        // debug launch arg `-mgzone green|yellow|red` forces the outcome (tests)
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-mgzone"), i + 1 < args.count,
           ["green", "yellow", "red"].contains(args[i + 1]) {
            zone = args[i + 1]
        }
        flash = zone
        if zone == "green" { AudioEngine.shared.success() }
        else if zone == "red" { AudioEngine.shared.fail() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onResolve(zone)
        }
    }
}
