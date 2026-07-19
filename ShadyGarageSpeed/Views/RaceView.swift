// RaceView.swift — race HUD (mirrors #screen-race on touch):
// timer, conditions, minimap, speed, NOS bar, countdown, forfeit, touch controls.
import SwiftUI

struct RaceView: View {
    @ObservedObject var scene: RaceScene

    private func bind(_ kp: ReferenceWritableKeyPath<RaceScene, Bool>) -> Binding<Bool> {
        let scene = self.scene // class reference; mutate through it, not through self
        return Binding(get: { scene[keyPath: kp] }, set: { scene[keyPath: kp] = $0 })
    }

    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.height < 520 || geo.size.width < 700
            let narrowCtl = geo.size.width < 400
            let btnD: CGFloat = compact ? (narrowCtl ? 60 : 64) : 74
            let ctlSpacing: CGFloat = narrowCtl ? 10 : 14
            let mapSize: CGFloat = compact ? 96 : 140
            let nosW: CGFloat = compact ? 90 : 120
            ZStack {
                SceneKitView(controller: scene)
                    .ignoresSafeArea()

                // timer + conditions, top center
                VStack(spacing: 2) {
                    Text(scene.raceTimerText)
                        .font(.system(size: compact ? 26 : 38, weight: .heavy, design: .monospaced))
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                    Text(scene.conditionsText)
                        .font(.system(size: compact ? 11 : 13, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                }
                .padding(.top, compact ? 2 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // minimap, top left
                minimap
                    .frame(width: mapSize, height: mapSize)
                    .background(Color(red: 10 / 255, green: 14 / 255, blue: 20 / 255).opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.leading, 12)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // forfeit, top right
                Button {
                    scene.forfeit()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                }
                .padding(.trailing, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .accessibilityLabel("Forfeit race")

                // speed + NOS, bottom right above the touch cluster
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("NOS")
                            .font(.system(size: 12, weight: .black))
                            .tracking(1)
                            .foregroundStyle(Color(rgb: 0x7dd3fc))
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(Color.sgsCyan)
                                .frame(width: nosW * CGFloat(min(100, max(0, scene.nosMeterInt))) / 100)
                        }
                        .frame(width: nosW, height: 10)
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text("\(scene.raceSpeedKmh)")
                            .font(.system(size: compact ? 38 : 54, weight: .black))
                        Text("km/h")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.sgsMuted)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                .padding(.trailing, 16)
                .padding(.bottom, btnD + 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)

                // countdown, center
                if let cd = scene.countdownText {
                    Text(cd)
                        .font(.system(size: compact ? 80 : 120, weight: .black))
                        .foregroundStyle(Color.sgsAccent)
                        .shadow(color: .black.opacity(0.7), radius: 20, y: 8)
                        .id(cd)
                        .transition(.scale.combined(with: .opacity))
                        .offset(y: -geo.size.height * 0.12)
                }

                // touch controls
                HStack(alignment: .bottom) {
                    HStack(spacing: ctlSpacing) {
                        HoldButton(label: "◀", tint: Color.sgsCard2, diameter: btnD,
                                   pressed: bind(\.inputLeft))
                        HoldButton(label: "▶", tint: Color.sgsCard2, diameter: btnD,
                                   pressed: bind(\.inputRight))
                    }
                    Spacer()
                    HStack(spacing: ctlSpacing) {
                        HoldButton(label: "NOS", tint: Color(rgb: 0x3b82f6), diameter: btnD,
                                   pressed: bind(\.inputNos))
                        HoldButton(label: "BRK", tint: Color(rgb: 0xef4444), diameter: btnD,
                                   pressed: bind(\.inputDown))
                        HoldButton(label: "GAS", tint: Color(rgb: 0x22c55e), diameter: btnD,
                                   pressed: bind(\.inputUp))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .animation(.spring(duration: 0.25), value: scene.countdownText)
        }
    }

    private var minimap: some View {
        Canvas { ctx, size in
            let pts = scene.minimapTrack
            if pts.count > 1 {
                var path = Path()
                path.move(to: CGPoint(x: pts[0].x * size.width, y: pts[0].y * size.height))
                for p in pts.dropFirst() {
                    path.addLine(to: CGPoint(x: p.x * size.width, y: p.y * size.height))
                }
                path.closeSubpath()
                ctx.stroke(path, with: .color(.white.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
            var tick = Path()
            let t0 = scene.minimapStartTick.0
            let t1 = scene.minimapStartTick.1
            tick.move(to: CGPoint(x: t0.x * size.width, y: t0.y * size.height))
            tick.addLine(to: CGPoint(x: t1.x * size.width, y: t1.y * size.height))
            ctx.stroke(tick, with: .color(Color.sgsAccent), lineWidth: 5)

            let pp = scene.minimapPlayer
            let c = CGPoint(x: pp.x * size.width, y: pp.y * size.height)
            let r: CGFloat = 4.5
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color.sgsAccent))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
        }
    }
}
