// RaceView.swift — race HUD (mirrors #screen-race on touch):
// timer, conditions, minimap, speed, NOS bar, countdown, forfeit, touch controls.
import SwiftUI

struct RaceView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var scene: RaceScene
    @ObservedObject private var audio = AudioEngine.shared
    var thermal = false

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
                SceneKitView(controller: scene, fps: 60, thermal: thermal)
                    .ignoresSafeArea()

                // timer + conditions, top center
                VStack(spacing: 2) {
                    Text(scene.raceTimerText)
                        .font(.system(size: compact ? 26 : 38, weight: .heavy, design: .monospaced))
                        .monospacedDigit()
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
                        .accessibilityIdentifier("race-timer")
                    Text(scene.conditionsText)
                        .font(.system(size: compact ? 11 : 13, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                    if let challenge = scene.challengeText {
                        Text(challenge)
                            .font(.system(size: compact ? 11 : 13, weight: .heavy))
                            .tracking(1)
                            .foregroundStyle(Color(rgb: 0xf472b6))
                            .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
                            .accessibilityIdentifier("pinkslip-banner")
                    }
                }
                .padding(.top, compact ? 2 : 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                // pause (top left, above the minimap)
                VStack(spacing: 10) {
                    Button {
                        scene.setPaused(true)
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                    }
                    .accessibilityLabel("Pause race")
                    .accessibilityIdentifier("race-pause")
                    .disabled(scene.runPhase == "finished" || scene.paused)

                    // minimap (static outline image cached once per size;
                    // per-frame redraw is just the player dot)
                    minimap(size: mapSize)
                        .frame(width: mapSize, height: mapSize)
                        .background(Color(red: 10 / 255, green: 14 / 255, blue: 20 / 255).opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .padding(.leading, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // mute + forfeit, top right
                HStack(spacing: 10) {
                    Button {
                        audio.toggleMute()
                    } label: {
                        Image(systemName: audio.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.black.opacity(0.45))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.5))
                    }
                    .accessibilityLabel("Toggle sound")
                    .accessibilityIdentifier("mute-toggle")

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
                    .accessibilityLabel("Forfeit race")
                    .accessibilityIdentifier("forfeit")
                    // during the finish roll the results screen is coming — no forfeit
                    .disabled(scene.runPhase == "finished")
                    .opacity(scene.runPhase == "finished" ? 0.35 : 1)
                }
                .padding(.trailing, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

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
                            .monospacedDigit()
                            .accessibilityIdentifier("race-speed")
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
                                   a11y: "tc-left", pressed: bind(\.inputLeft))
                        HoldButton(label: "▶", tint: Color.sgsCard2, diameter: btnD,
                                   a11y: "tc-right", pressed: bind(\.inputRight))
                    }
                    Spacer()
                    HStack(spacing: ctlSpacing) {
                        HoldButton(label: "NOS", tint: Color(rgb: 0x3b82f6), diameter: btnD,
                                   a11y: "tc-nos", pressed: bind(\.inputNos))
                        HoldButton(label: "BRK", tint: Color(rgb: 0xef4444), diameter: btnD,
                                   a11y: "tc-brake", pressed: bind(\.inputDown))
                        HoldButton(label: "GAS", tint: Color(rgb: 0x22c55e), diameter: btnD,
                                   a11y: "tc-gas", pressed: bind(\.inputUp))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                // pause overlay: sim frozen, timer held, loops silenced (topmost)
                if scene.paused {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 14) {
                        Text("PAUSED")
                            .font(.system(size: 28, weight: .black))
                            .tracking(3)
                        Text(scene.raceTimerText)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(Color.sgsMuted)
                        SGSButton(title: "Resume", big: true, a11y: "pause-resume") {
                            scene.setPaused(false)
                        }
                        SGSButton(title: "Forfeit", ghost: true, a11y: "pause-forfeit") {
                            scene.setPaused(false)
                            scene.forfeit()
                        }
                        SGSButton(title: "Quit to Menu", ghost: true, a11y: "pause-quit") {
                            scene.setPaused(false)
                            scene.exitRace()
                            app.goMenu()
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: 340)
                    .background(Color.sgsPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pause-overlay")
                }
            }
            .animation(.spring(duration: 0.25), value: scene.countdownText)
        }
    }

    private func minimap(size: CGFloat) -> some View {
        ZStack {
            if let img = Self.trackImage(track: scene.minimapTrack,
                                         tick: scene.minimapStartTick, side: size) {
                Image(uiImage: img)
                    .resizable()
                    .frame(width: size, height: size)
            }
            Canvas { ctx, canvasSize in
                let pp = scene.minimapPlayer
                let c = CGPoint(x: pp.x * canvasSize.width, y: pp.y * canvasSize.height)
                let r: CGFloat = 4.5
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color.sgsAccent))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 2)
            }
        }
    }

    /// Static track outline + start tick, rendered once per size (the old code
    /// restroked 800 segments at 30Hz).
    private static var trackImageCache: [Int: UIImage] = [:]

    private static func trackImage(track: [CGPoint], tick: (CGPoint, CGPoint), side: CGFloat) -> UIImage? {
        let key = Int(side)
        if let cached = trackImageCache[key] { return cached }
        guard track.count > 1 else { return nil }
        let scale = UIScreen.main.scale
        let px = CGSize(width: side * scale, height: side * scale)
        let img = UIGraphicsImageRenderer(size: px).image { renderer in
            let c = renderer.cgContext
            c.scaleBy(x: scale, y: scale)
            c.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
            c.setLineWidth(3)
            c.setLineJoin(.round)
            c.beginPath()
            c.move(to: CGPoint(x: track[0].x * side, y: track[0].y * side))
            for p in track.dropFirst() {
                c.addLine(to: CGPoint(x: p.x * side, y: p.y * side))
            }
            c.closePath()
            c.strokePath()
            c.setStrokeColor(UIColor(Color.sgsAccent).cgColor)
            c.setLineWidth(5)
            c.beginPath()
            c.move(to: CGPoint(x: tick.0.x * side, y: tick.0.y * side))
            c.addLine(to: CGPoint(x: tick.1.x * side, y: tick.1.y * side))
            c.strokePath()
        }
        trackImageCache[key] = img
        return img
    }
}
