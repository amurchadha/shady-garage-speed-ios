// StealMinigameView.swift — stealth timing minigame (mirrors #modal-minigame).
// Marker sweeps 0–100% at 95%/s; green zone 18% at G∈[12,70], yellow 9% flanks.
import SwiftUI

struct StealMinigameView: View {
    let title: String
    let onResolve: (String) -> Void // "green" | "yellow" | "red"

    @State private var g: Double = 30        // green zone left edge, %
    @State private var pos: Double = 0       // marker, %
    @State private var dir: Double = 1
    @State private var flash: String? = nil
    @State private var resolved = false

    private let ticker = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.opacity(0.66).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.title3.bold())
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.sgsBad.opacity(0.45))
                        zoneRect(x: g - 9, w: 9, color: Color.sgsWarn.opacity(0.65), in: geo)
                        zoneRect(x: g, w: 18, color: Color.sgsGood.opacity(0.85), in: geo)
                        zoneRect(x: g + 18, w: 9, color: Color.sgsWarn.opacity(0.65), in: geo)
                        Rectangle()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                            .frame(width: 4)
                            .offset(x: geo.size.width * CGFloat(pos) / 100 - 2)
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
            g = 12 + Double.random(in: 0..<58)
            pos = Double.random(in: 0..<100)
            dir = Double.random(in: 0..<1) < 0.5 ? 1 : -1
        }
        .onReceive(ticker) { _ in
            guard !resolved else { return }
            pos += dir * 95 * (1.0 / 60)
            if pos >= 100 { pos = 100; dir = -1 }
            if pos <= 0 { pos = 0; dir = 1 }
        }
    }

    private func zoneRect(x: Double, w: Double, color: Color, in geo: GeometryProxy) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: geo.size.width * CGFloat(w) / 100)
            .offset(x: geo.size.width * CGFloat(x) / 100)
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
        if pos >= g && pos <= g + 18 {
            zone = "green"
        } else if (pos >= g - 9 && pos < g) || (pos > g + 18 && pos <= g + 27) {
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
